import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../models/rider.dart';
import '../../services/location_service.dart';
import '../../services/rider_location_task.dart';
import '../../services/ratings_service.dart';
import '../../widgets/delivery_trip_summary.dart';
import '../../widgets/rating_sheet.dart';
import '../shared/bank_account_page.dart';
import '../shared/change_password_page.dart';
import '../shared/support_tickets_page.dart';
import 'earnings_widgets.dart';
import 'profile_page.dart';
import 'rider_map_page.dart';

class RiderDashboardPage extends StatefulWidget {
  const RiderDashboardPage({super.key});
  @override
  State<RiderDashboardPage> createState() => _RiderDashboardPageState();
}

class _RiderDashboardPageState extends State<RiderDashboardPage>
    with TickerProviderStateMixin {
  final _db   = Supabase.instance.client;
  final _auth = Get.find<AuthController>();
  int _tab = 0;
  late final TabController _jobsTabController;
  late final TabController _earningsTabController;

  Rider? get _rider => _auth.rider.value;

  List<Map<String, dynamic>> _openDeliveries   = [];
  List<Map<String, dynamic>> _activeDeliveries = [];
  List<Map<String, dynamic>> _jobHistory       = [];
  List<Map<String, dynamic>> _pendingInvites   = [];
  List<Map<String, dynamic>> _payoutHistory    = [];
  List<Map<String, dynamic>> _myRatings        = [];

  double? _riderLat;
  double? _riderLng;
  static const _kMaxRadiusKm = 50.0;

  bool _loading         = true;
  bool _toggling        = false;
  bool _actionLoading   = false;
  bool _inviteLoading   = false;
  bool _payoutLoading   = false;
  bool _isOnline        = false;
  bool _isCompanyRider  = false;

  StreamSubscription<Position>? _locationSub;
  Timer? _heartbeatTimer;
  Timer? _confirmedPollTimer; // fallback for missed Realtime confirmed events
  RealtimeChannel? _channel;       // deliveries UPDATE (active delivery status)
  RealtimeChannel? _openChannel;  // deliveries INSERT  (new open jobs)
  RealtimeChannel? _bidChannel;   // delivery_bids UPDATE (bid accepted)
  RealtimeChannel? _inviteChannel; // company_rider_invites INSERT

  @override
  void initState() {
    super.initState();
    _jobsTabController = TabController(length: 3, vsync: this);
    _earningsTabController = TabController(length: 2, vsync: this);
    _isOnline = _rider?.isAvailable ?? false;
    _initForegroundTask();
    _load();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rider_location',
        channelName: 'Rider Location Service',
        channelDescription: 'Keeps your location active for delivery requests',
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _heartbeatTimer?.cancel();
    _confirmedPollTimer?.cancel();
    if (_channel       != null) _db.removeChannel(_channel!);
    if (_openChannel   != null) _db.removeChannel(_openChannel!);
    if (_bidChannel    != null) _db.removeChannel(_bidChannel!);
    if (_inviteChannel != null) _db.removeChannel(_inviteChannel!);
    _jobsTabController.dispose();
    _earningsTabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rider = _rider;
      if (rider == null) {
        setState(() => _loading = false);
        return;
      }
      final riderId = rider.id;
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;

      // Rider's live GPS
      final locRow = await _db
          .from('rider_locations')
          .select('latitude, longitude')
          .eq('rider_id', uid)
          .maybeSingle();
      _riderLat = (locRow?['latitude']  as num?)?.toDouble();
      _riderLng = (locRow?['longitude'] as num?)?.toDouble();

      // Active deliveries assigned to this rider
      final activeRes = await _db
          .from('deliveries')
          .select()
          .eq('rider_id', riderId)
          .inFilter('status',
              ['assigned', 'awaiting_pickup_confirm', 'picked_up', 'delivered'])
          .order('created_at', ascending: false);
      _activeDeliveries = List<Map<String, dynamic>>.from(activeRes);

      // Open deliveries for bidding
      final openRes = await _db
          .from('deliveries')
          .select()
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(50);
      final all = List<Map<String, dynamic>>.from(openRes);
      final filtered = all.where(_withinRadius).toList();
      if (_riderLat != null) {
        filtered.sort((a, b) {
          final dA = _pickupDistance(a) ?? double.infinity;
          final dB = _pickupDistance(b) ?? double.infinity;
          return dA.compareTo(dB);
        });
      }
      _openDeliveries = filtered;

      // Pending company invites (rider_id = auth.uid in this table)
      final inviteRes = await _db
          .from('company_rider_invites')
          .select('*, company:companies(name)')
          .eq('rider_id', uid)
          .eq('status', 'pending');
      _pendingInvites = List<Map<String, dynamic>>.from(inviteRes);

      // Company membership — accepted invite means this rider works for a company
      final memberRes = await _db
          .from('company_rider_invites')
          .select('id')
          .eq('rider_id', uid)
          .eq('status', 'accepted')
          .limit(1);
      final wasCompanyRider = _isCompanyRider;
      _isCompanyRider = (memberRes as List).isNotEmpty;
      // If layout changes (solo ↔ company), reset tab to Home to avoid index mismatch
      if (wasCompanyRider != _isCompanyRider) _tab = 0;

      // Job history — only confirmed deliveries (customer-confirmed receipt).
      // 'delivered' stays in _activeDeliveries until the customer confirms,
      // so we never double-count a delivery in both lists.
      final historyRes = await _db
          .from('deliveries')
          .select()
          .eq('rider_id', riderId)
          .eq('status', 'confirmed')
          .order('created_at', ascending: false)
          .limit(20);
      _jobHistory = List<Map<String, dynamic>>.from(historyRes);

      // Payout history
      final payoutRes = await _db
          .from('rider_payout_requests')
          .select()
          .eq('rider_id', riderId)
          .order('created_at', ascending: false);
      _payoutHistory = List<Map<String, dynamic>>.from(payoutRes);

      // Ratings left on me — who rated, their stars, and their comment.
      final ratingsRes = await _db
          .from('delivery_ratings')
          .select()
          .eq('ratee_id', riderId)
          .eq('ratee_role', 'rider')
          .order('created_at', ascending: false);
      _myRatings = List<Map<String, dynamic>>.from(ratingsRes);
    } catch (_) {}

    setState(() => _loading = false);

    // Auto-start GPS when rider has an active delivery (covers app-reopen after bid accepted).
    // Pass silentIfNotGranted=true so we never show a permission dialog silently;
    // if permission isn't already granted the rider must toggle Online manually.
    if ((_isOnline || _activeDeliveries.isNotEmpty) && _locationSub == null) {
      _startLocationBroadcast(silentIfNotGranted: !_isOnline);
    }
    _subscribeRealtime();

    // If any delivery is sitting in 'delivered', start the confirmed-poll fallback
    // in case the Realtime confirmed event was missed.
    if (_activeDeliveries.any((d) => d['status'] == 'delivered')) {
      _startConfirmedPoll();
    }
  }

  // Checks the DB right now for any 'delivered' deliveries that are actually
  // already 'confirmed'. Clears them immediately and cancels the poll timer.
  // Called right after _load() and from the periodic poll timer.
  Future<void> _checkConfirmed() async {
    final ids = _activeDeliveries
        .where((d) => d['status'] == 'delivered')
        .map((d) => d['id'] as String)
        .toList();
    if (ids.isEmpty) {
      _confirmedPollTimer?.cancel();
      _confirmedPollTimer = null;
      return;
    }
    try {
      final rows = await _db
          .from('deliveries')
          .select('id, status')
          .inFilter('id', ids);
      final confirmedIds = (rows as List)
          .where((r) => r['status'] == 'confirmed')
          .map((r) => r['id'] as String)
          .toSet();
      if (confirmedIds.isNotEmpty && mounted) {
        final confirmed = _activeDeliveries
            .where((d) => confirmedIds.contains(d['id'] as String))
            .toList();
        setState(() {
          _activeDeliveries.removeWhere((d) => confirmedIds.contains(d['id'] as String));
          for (final d in confirmed) {
            if (!_jobHistory.any((h) => h['id'] == d['id'])) {
              _jobHistory.insert(0, d);
            }
          }
        });
        // Wallet balance was just credited by the earnings trigger —
        // refresh the profile so "Available Balance" isn't stale. _rider is
        // a plain (non-Obx) getter here, so the refreshed value needs its
        // own setState to actually show up on screen.
        await _auth.refreshProfile();
        if (mounted) setState(() {});
        for (final d in confirmed) {
          _maybeShowRateCustomerSheet(d['id'] as String);
        }
        _confirmedPollTimer?.cancel();
        _confirmedPollTimer = null;
        if (_activeDeliveries.isEmpty) _stopLocationBroadcast();
      }
    } catch (_) {}
  }

  // Rider rates the receiver once a delivery reaches 'confirmed'. This lives
  // here (not just in rider_map_page.dart) because the confirming customer
  // can act long after the rider has left the map page (e.g. an SMS/OTP
  // failure forces a delayed fallback confirm) — if nothing is listening by
  // then, the rider never gets prompted. Dashboard is alive whenever the
  // rider has the app open, so it's the reliable place to catch this.
  Future<void> _maybeShowRateCustomerSheet(String deliveryId) async {
    final already = await RatingsService.hasRated(
        deliveryId: deliveryId, checkpoint: 'delivery', raterRole: 'rider');
    if (already || !mounted) return;
    final user = _db.auth.currentUser;
    final rider = _rider;
    if (user == null || rider == null) return;
    if (!mounted) return;
    showRatingSheet(
      context,
      title: 'Rate the Receiver',
      subtitle: 'How was your delivery experience?',
      onSubmit: (rating, comment) => RatingsService.submit(
        deliveryId: deliveryId,
        checkpoint: 'delivery',
        raterAuthId: user.id,
        raterRole: 'rider',
        raterName: rider.fullName,
        rateeRole: 'receiver',
        rateeId: null,
        rating: rating,
        comment: comment,
      ),
    );
  }

  // Runs an immediate check then polls every 12 s as a fallback for missed
  // Realtime confirmed events (Supabase Realtime is at-most-once delivery).
  void _startConfirmedPoll() {
    _checkConfirmed(); // immediate — clears card right away if already confirmed
    _confirmedPollTimer?.cancel();
    _confirmedPollTimer = Timer.periodic(
        const Duration(seconds: 12), (_) => _checkConfirmed());
  }

  void _subscribeRealtime() {
    if (_channel       != null) { _db.removeChannel(_channel!);       _channel       = null; }
    if (_openChannel   != null) { _db.removeChannel(_openChannel!);   _openChannel   = null; }
    if (_bidChannel    != null) { _db.removeChannel(_bidChannel!);    _bidChannel    = null; }
    if (_inviteChannel != null) { _db.removeChannel(_inviteChannel!); _inviteChannel = null; }

    final uid   = _db.auth.currentUser?.id;
    final rider = _rider;
    if (uid == null || rider == null) return;
    final riderId = rider.id;

    // ── Channel A: open job board ─────────────────────────────────────────────
    // Receives INSERT events so new packages appear instantly, no filter needed
    // (all authenticated riders can read open deliveries via RLS).
    _openChannel = _db
        .channel('rider_open_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'deliveries',
          callback: (payload) {
            final d = Map<String, dynamic>.from(payload.newRecord);
            if (!mounted) return;
            if (d['status'] == 'open' &&
                !_openDeliveries.any((r) => r['id'] == d['id']) &&
                _withinRadius(d)) {
              setState(() => _openDeliveries.insert(0, d));
            }
          })
        // Someone else won this delivery (or it was cancelled) — Channel B
        // only catches rows assigned to THIS rider, so a delivery this rider
        // bid on and lost would otherwise sit in _openDeliveries forever.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          callback: (payload) {
            final d = Map<String, dynamic>.from(payload.newRecord);
            if (!mounted) return;
            if (d['status'] != 'open') {
              setState(() => _openDeliveries.removeWhere((r) => r['id'] == d['id']));
            }
          })
        .subscribe();

    // ── Channel B: this rider's active delivery updates ───────────────────────
    // Server-side filter (rider_id = riderId) so only events that pass RLS for
    // THIS rider are sent, avoiding the silent-drop problem with unfiltered subs.
    _channel = _db
        .channel('rider_active_$riderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'rider_id',
            value:  riderId,
          ),
          callback: (payload) async {
            final d = Map<String, dynamic>.from(payload.newRecord);
            if (!mounted) return;
            final newStatus = d['status'] as String? ?? '';

            // Delivery just assigned to me — move from open list to active
            if (newStatus == 'assigned' &&
                !_activeDeliveries.any((r) => r['id'] == d['id'])) {
              setState(() {
                _openDeliveries.removeWhere((r) => r['id'] == d['id']);
                _activeDeliveries.insert(0, d);
              });
              Get.snackbar('Bid Accepted! 🎉',
                  'You have been assigned a delivery. Head to pickup.',
                  backgroundColor: EzizaColors.kSuccess,
                  colorText: EzizaColors.kWhite,
                  duration: const Duration(seconds: 5),
                  snackPosition: SnackPosition.BOTTOM);
              if (_locationSub == null) _startLocationBroadcast();
              return;
            }

            // Update active delivery row in-place (picked_up, delivered, etc.)
            final idx = _activeDeliveries.indexWhere((r) => r['id'] == d['id']);
            if (idx == -1) {
              // This row matches our rider_id filter (so it's genuinely ours)
              // but wasn't caught by the "just assigned" branch above — e.g.
              // a company assigning us to a job it already won, where the
              // earlier 'assigned' event had rider_id still null and only
              // this later update actually set it to us. Don't just drop
              // it silently: if it's a trackable en-route status, adopt it
              // the same way, so location broadcasting still starts.
              const enRoute = ['assigned', 'awaiting_pickup_confirm', 'picked_up'];
              if (enRoute.contains(newStatus)) {
                setState(() {
                  _openDeliveries.removeWhere((r) => r['id'] == d['id']);
                  _activeDeliveries.insert(0, d);
                });
                if (_locationSub == null) _startLocationBroadcast();
              }
              return;
            }
            if (newStatus == 'confirmed') {
              setState(() {
                _activeDeliveries.removeAt(idx);
                if (!_jobHistory.any((h) => h['id'] == d['id'])) {
                  _jobHistory.insert(0, d);
                }
              });
              // Wallet balance was just credited by the earnings trigger —
              // refresh the profile so "Available Balance" isn't stale. _rider
              // is a plain (non-Obx) getter here, so the refreshed value
              // needs its own setState to actually show up on screen.
              await _auth.refreshProfile();
              if (mounted) setState(() {});
              _maybeShowRateCustomerSheet(d['id'] as String);
              _confirmedPollTimer?.cancel();
              _confirmedPollTimer = null;
              if (_activeDeliveries.isEmpty) {
                await FlutterForegroundTask.updateService(
                  notificationTitle: 'Delivery Complete ✅',
                  notificationText: 'Great work! Earnings credited.',
                );
                await Future.delayed(const Duration(seconds: 3));
                _stopLocationBroadcast();
              }
            } else {
              setState(() => _activeDeliveries[idx] = d);
              // If status just became 'delivered', start the poll fallback.
              if (newStatus == 'delivered') _startConfirmedPoll();
            }
          })
        .subscribe();

    // ── Channel D: company invite notifications ───────────────────────────────
    // Separate channel — one table per channel avoids Supabase Realtime
    // silent-drop bugs that occur with mixed-table subscriptions.
    _inviteChannel = _db
        .channel('rider_invite_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'company_rider_invites',
          callback: (payload) async {
            final invite = Map<String, dynamic>.from(payload.newRecord);
            if (invite['rider_id'] != uid || !mounted) return;
            _onNewInvite(invite['id'] as int);
          })
        .subscribe();

    // ── Channel C: bid accepted ───────────────────────────────────────────────
    // Separate channel so mixed-table subscriptions don't conflict.
    // delivery_bids.rider_id is stable (set at bid time, never changes), so
    // the eq filter always matches both old AND new records on UPDATE — reliable.
    _bidChannel = _db
        .channel('rider_bid_$riderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'delivery_bids',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'rider_id',
            value:  riderId,
          ),
          callback: (payload) async {
            final bid = Map<String, dynamic>.from(payload.newRecord);
            if (!mounted) return;
            if ((bid['status'] as String?) != 'accepted') return;
            final delivId = bid['delivery_id'] as String?;
            if (delivId == null) return;
            if (_activeDeliveries.any((r) => r['id'] == delivId)) return;
            final delivery = await _db
                .from('deliveries')
                .select()
                .eq('id', delivId)
                .maybeSingle();
            if (delivery == null || !mounted) return;
            // Re-check after the await: Channel B (deliveries UPDATE) listens
            // for the same "bid accepted" transition and can win the race
            // while this fetch was in flight, inserting the same delivery
            // first — without this, both channels would insert a duplicate.
            if (_activeDeliveries.any((r) => r['id'] == delivId)) return;
            final d = Map<String, dynamic>.from(delivery);
            setState(() {
              _openDeliveries.removeWhere((r) => r['id'] == delivId);
              _activeDeliveries.insert(0, d);
            });
            Get.snackbar('Bid Accepted! 🎉',
                'You have been assigned a delivery. Head to pickup.',
                backgroundColor: EzizaColors.kSuccess,
                colorText: EzizaColors.kWhite,
                duration: const Duration(seconds: 5),
                snackPosition: SnackPosition.BOTTOM);
            if (_locationSub == null) _startLocationBroadcast();
          })
        .subscribe();
  }

  Future<void> _onNewInvite(int inviteId) async {
    try {
      final invite = await _db
          .from('company_rider_invites')
          .select('*, company:companies(name)')
          .eq('id', inviteId)
          .maybeSingle();
      if (invite != null &&
          mounted &&
          !_pendingInvites.any((i) => i['id'] == inviteId)) {
        setState(() => _pendingInvites.insert(0, invite));
        final name =
            (invite['company'] as Map?)?['name'] ?? 'A company';
        Get.snackbar('Company Invite',
            '$name invited you to join their team.',
            backgroundColor: EzizaColors.kPurple,
            colorText: EzizaColors.kWhite,
            duration: const Duration(seconds: 5),
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (_) {}
  }

  Future<void> _toggleOnline() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    final newVal = !_isOnline;
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      await _db
          .from('riders')
          .update({'is_available': newVal})
          .eq('auth_user_id', uid);
      setState(() => _isOnline = newVal);
      if (newVal) {
        _startLocationBroadcast();
      } else {
        await _stopLocationBroadcast();
      }
    } catch (_) {}
    setState(() => _toggling = false);
  }

  Future<bool> _showBackgroundLocationDisclosure() async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            contentPadding:
                const EdgeInsets.fromLTRB(24, 24, 24, 0),
            actionsPadding:
                const EdgeInsets.fromLTRB(16, 8, 16, 16),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: EzizaColors.kPurple.withValues(alpha: 0.08),
                    shape: BoxShape.circle),
                child: const Icon(Icons.location_on_rounded,
                    color: EzizaColors.kPurple, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('Background Location Access',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: EzizaColors.kText)),
              const SizedBox(height: 12),
              const Text(
                'Eziza needs to access your location in the background '
                'so we can track your delivery route when you lock your screen '
                'or switch to another app.\n\n'
                'Your location is only shared while you are online and is '
                'used to match you with nearby delivery requests.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: EzizaColors.kMuted,
                    height: 1.5),
              ),
              const SizedBox(height: 4),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Not Now',
                    style: TextStyle(color: EzizaColors.kMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: EzizaColors.kPurple,
                    foregroundColor: EzizaColors.kWhite,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Allow Location'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _startLocationBroadcast({bool silentIfNotGranted = false}) async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      if (!silentIfNotGranted && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Location Permission Required'),
            content: const Text(
              'Location permission was permanently denied. Please open '
              'Settings and grant location permission to go online.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Geolocator.openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: EzizaColors.kPurple,
                    foregroundColor: EzizaColors.kWhite),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return;
    }
    if (perm == LocationPermission.denied) {
      if (silentIfNotGranted) return;
      final agreed = await _showBackgroundLocationDisclosure();
      if (!agreed) return;
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;

    final initialPos = await LocationService.getCurrentPosition();
    if (initialPos != null) await _upsertLocation(uid, initialPos);

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) => _upsertLocation(uid, pos));

    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) await _upsertLocation(uid, pos);
    });

    await _startForegroundService(uid);
  }

  Future<void> _startForegroundService(String uid) async {
    try {
      await FlutterForegroundTask.saveData(
          key: 'sb_url',
          value: 'https://nvwpsccleewgirlwokys.supabase.co');
      await FlutterForegroundTask.saveData(
          key: 'sb_anon_key',
          value: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
              '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im52d3BzY2NsZWV3Z2lybHdva3lzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MTkwMzAsImV4cCI6MjA5ODM5NTAzMH0'
              '.l5ubcS_xLNdQ_MmkQCDzvcgPIb_DJI1ei6yc3yqqtWk');
      await FlutterForegroundTask.saveData(key: 'rider_id', value: uid);
      final hasActive = _activeDeliveries.isNotEmpty;
      await FlutterForegroundTask.startService(
        notificationTitle:
            hasActive ? 'Active Delivery 🚀' : 'You are online',
        notificationText: hasActive
            ? 'Tracking your location to pickup point'
            : 'Location tracking active for delivery requests',
        callback: startRiderLocationCallback,
      );
    } catch (_) {}
  }

  Future<void> _upsertLocation(String uid, Position pos) async {
    try {
      await _db.from('rider_locations').upsert({
        'rider_id':   uid,
        'latitude':   pos.latitude,
        'longitude':  pos.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        final firstFix = _riderLat == null;
        setState(() {
          _riderLat = pos.latitude;
          _riderLng = pos.longitude;
        });
        // First GPS fix — reload open deliveries so the radius filter can apply.
        // Until this point _withinRadius() returns false (unknown location),
        // so the job board was empty.
        if (firstFix) _reloadOpenDeliveries();
      }
    } catch (_) {}
  }

  Future<void> _reloadOpenDeliveries() async {
    try {
      final openRes = await _db
          .from('deliveries')
          .select()
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(50);
      final all      = List<Map<String, dynamic>>.from(openRes);
      final filtered = all.where(_withinRadius).toList();
      filtered.sort((a, b) {
        final dA = _pickupDistance(a) ?? double.infinity;
        final dB = _pickupDistance(b) ?? double.infinity;
        return dA.compareTo(dB);
      });
      if (mounted) setState(() => _openDeliveries = filtered);
    } catch (_) {}
  }

  Future<void> _stopLocationBroadcast() async {
    await _locationSub?.cancel();
    _locationSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    // Remove stale GPS row so customers can no longer read this rider's location.
    final uid = _db.auth.currentUser?.id;
    if (uid != null) {
      try {
        await _db.from('rider_locations').delete().eq('rider_id', uid);
      } catch (_) {}
    }
  }

  Future<void> _markStatus(String deliveryId, String newStatus) async {
    setState(() => _actionLoading = true);
    try {
      await _db
          .from('deliveries')
          .update({'status': newStatus})
          .eq('id', deliveryId);
      final msg = switch (newStatus) {
        'awaiting_pickup_confirm' => ('Merchant Notified',
            'Waiting for merchant to confirm handoff.',
            const Color(0xFFD97706)),
        'picked_up' =>
          ('Picked Up', 'Package marked as picked up.', EzizaColors.kSuccess),
        'delivered' => (
            'Delivered',
            'Package marked delivered. Awaiting customer confirmation.',
            EzizaColors.kSuccess),
        _ => ('Updated', 'Status updated.', EzizaColors.kSuccess),
      };
      Get.snackbar(msg.$1, msg.$2,
          backgroundColor: msg.$3,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
      await _load();
      // After marking delivered, watch for customer confirmation in case
      // the Realtime confirmed event is missed (at-most-once delivery).
      if (newStatus == 'delivered') _startConfirmedPoll();
    } catch (_) {
      Get.snackbar('Error', 'Could not update status. Try again.',
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
    }
    setState(() => _actionLoading = false);
  }

  Future<void> _respondInvite(int inviteId, bool accept) async {
    setState(() => _inviteLoading = true);
    try {
      await _db
          .from('company_rider_invites')
          .update({'status': accept ? 'accepted' : 'declined'})
          .eq('id', inviteId);
      Get.snackbar(
        accept ? 'Welcome to the team!' : 'Declined',
        accept ? 'You have joined the company.' : 'Invite declined.',
        backgroundColor:
            accept ? EzizaColors.kSuccess : EzizaColors.kMuted,
        colorText: EzizaColors.kWhite,
        snackPosition: SnackPosition.BOTTOM,
      );
      await _load();
    } catch (_) {
      Get.snackbar('Error', 'Could not process invite.',
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
    }
    setState(() => _inviteLoading = false);
  }

  void _showPayoutSheet() {
    final amtCtrl = TextEditingController();
    final pendingPayout = _payoutHistory
        .where((p) => ['pending', 'approved'].contains(p['status']))
        .fold<double>(0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));
    final balance = ((_rider?.walletBalance ?? 0.0) - pendingPayout)
        .clamp(0, double.infinity);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Request Payout',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: EzizaColors.kText)),
                const SizedBox(height: 4),
                Text('Available: ₦${balance.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 13, color: EzizaColors.kMuted)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: EzizaColors.kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EzizaColors.kBorder)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payout to',
                            style: TextStyle(
                                fontSize: 11,
                                color: EzizaColors.kMuted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_rider?.accountName ?? '—',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: EzizaColors.kText)),
                        Text(
                            '${_rider?.bankName ?? ''} · ${_rider?.accountNumber ?? '—'}'
                                .trim(),
                            style: const TextStyle(
                                fontSize: 12,
                                color: EzizaColors.kMuted)),
                      ]),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                      color: EzizaColors.kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EzizaColors.kBorder)),
                  child: TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(
                        fontSize: 14, color: EzizaColors.kText),
                    decoration: const InputDecoration(
                      prefixText: '₦ ',
                      prefixStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: EzizaColors.kPurpleD),
                      hintText: 'Enter amount',
                      hintStyle: TextStyle(
                          color: EzizaColors.kMuted, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                setSheet == setSheet && _payoutLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: EzizaColors.kPurpleD))
                    : GestureDetector(
                        onTap: () async {
                          final amt =
                              double.tryParse(amtCtrl.text.trim());
                          if (amt == null || amt <= 0) {
                            Get.snackbar(
                                'Invalid', 'Enter a valid amount',
                                backgroundColor: EzizaColors.kError,
                                colorText: EzizaColors.kWhite,
                                snackPosition: SnackPosition.BOTTOM);
                            return;
                          }
                          if (amt > balance) {
                            Get.snackbar('Insufficient',
                                'Amount exceeds your balance',
                                backgroundColor: EzizaColors.kError,
                                colorText: EzizaColors.kWhite,
                                snackPosition: SnackPosition.BOTTOM);
                            return;
                          }
                          Navigator.of(ctx).pop();
                          setState(() => _payoutLoading = true);
                          try {
                            await _db
                                .from('rider_payout_requests')
                                .insert({
                              'rider_id': _rider!.id,
                              'amount': amt,
                            });
                            Get.snackbar('Request Submitted',
                                'Your payout request is pending admin approval.',
                                backgroundColor: EzizaColors.kSuccess,
                                colorText: EzizaColors.kWhite,
                                snackPosition: SnackPosition.BOTTOM);
                            await _load();
                          } catch (_) {
                            Get.snackbar('Request failed',
                                'Could not submit payout request. Please try again.',
                                backgroundColor: EzizaColors.kError,
                                colorText: EzizaColors.kWhite,
                                snackPosition: SnackPosition.BOTTOM);
                          }
                          setState(() => _payoutLoading = false);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                EzizaColors.kPurple,
                                EzizaColors.kPurpleD
                              ]),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                    color: EzizaColors.kPurpleD
                                        .withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4))
                              ]),
                          child: const Center(
                              child: Text('Submit Request',
                                  style: TextStyle(
                                      color: EzizaColors.kWhite,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15))),
                        ),
                      ),
              ]),
        );
      }),
    );
  }

  void _showBidSheet(Map<String, dynamic> delivery) {
    if (_isCompanyRider) {
      Get.snackbar(
        'Bidding Disabled',
        'You\'re part of a company fleet. Your company bids on deliveries on your behalf.',
        backgroundColor: EzizaColors.kPurpleD,
        colorText: EzizaColors.kWhite,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final amtCtrl  = TextEditingController();
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Place a Bid',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: EzizaColors.kText)),
          const SizedBox(height: 16),
          DeliveryTripSummary(
              delivery: delivery, riderLat: _riderLat, riderLng: _riderLng),
          const SizedBox(height: 16),
          TextField(
            controller: amtCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Your price (₦)',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: EzizaColors.kPurple,
                  foregroundColor: EzizaColors.kWhite,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final amount = double.tryParse(amtCtrl.text.trim());
                if (amount == null) return;
                Navigator.pop(ctx);
                try {
                  await _db.from('delivery_bids').upsert({
                    'delivery_id': delivery['id'],
                    'rider_id':    _rider!.id,
                    'amount':      amount,
                    'status':      'pending',
                    'note': noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                  }, onConflict: 'delivery_id,rider_id');
                  Get.snackbar('Bid placed',
                      'Your bid has been submitted.',
                      backgroundColor: EzizaColors.kSuccess,
                      colorText: EzizaColors.kWhite,
                      snackPosition: SnackPosition.BOTTOM);
                } catch (_) {
                  Get.snackbar('Could not place bid',
                      'Please try again.',
                      backgroundColor: EzizaColors.kError,
                      colorText: EzizaColors.kWhite,
                      snackPosition: SnackPosition.BOTTOM);
                }
              },
              child: const Text('Submit Bid'),
            ),
          ),
        ]),
        ),
      ),
    );
  }

  // ── Geo helpers ───────────────────────────────────────────────

  static double _distKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double? _pickupDistance(Map<String, dynamic> d) {
    final rLat = _riderLat;
    final rLng = _riderLng;
    if (rLat == null || rLng == null) return null;
    final pLat = (d['pickup_lat'] as num?)?.toDouble();
    final pLng = (d['pickup_lng'] as num?)?.toDouble();
    if (pLat == null || pLng == null) return null;
    return _distKm(rLat, rLng, pLat, pLng);
  }

  bool _withinRadius(Map<String, dynamic> d) {
    // State-based match: rider explicitly covers the pickup state.
    // This handles interstate riders and city riders with a defined coverage area.
    final pickupState = (d['pickup_state'] as String?)?.trim();
    if (pickupState != null && pickupState.isNotEmpty) {
      final coverage = _rider?.coverageStates ?? [];
      if (coverage.any(
          (s) => s.trim().toLowerCase() == pickupState.toLowerCase())) {
        return true;
      }
    }

    // GPS radius fallback: rider is within 50 km of the pickup point.
    // If no GPS yet we don't know the rider's position — don't show.
    if (_riderLat == null || _riderLng == null) return false;
    final dist = _pickupDistance(d);
    if (dist == null) return true; // delivery has no coords — show it
    return dist <= _kMaxRadiusKm;
  }

  String _ago(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: IndexedStack(
        index: _tab,
        children: _isCompanyRider
            ? [_homeTab(), _jobsTab(), _accountTab()]
            : [_homeTab(), _jobsTab(), _earningsTab(), _accountTab()],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() => Container(
    decoration: BoxDecoration(
      color: EzizaColors.kWhite,
      boxShadow: [
        BoxShadow(
          color: EzizaColors.kPurple.withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: BottomNavigationBar(
      currentIndex: _tab,
      onTap: (i) => setState(() => _tab = i),
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: EzizaColors.kPurpleD,
      unselectedItemColor: EzizaColors.kMuted,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.home_rounded),  label: 'Home'),
        const BottomNavigationBarItem(icon: Icon(Icons.work_rounded),   label: 'Jobs'),
        if (!_isCompanyRider)
          const BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_rounded), label: 'Earnings'),
        const BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Account'),
      ],
    ),
  );

  // ── Home tab helpers (customer-style) ────────────────────────

  Widget _riderHeaderWithStats() {
    final completed = _jobHistory.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _riderHomeHdr(),
        Positioned(
          bottom: -52, left: 20, right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            decoration: BoxDecoration(
              color: EzizaColors.kWhite,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(
                  color: const Color(0xFF6C3483).withValues(alpha: 0.15),
                  blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(children: [
              _hfStat('${_activeDeliveries.length}', 'Active',
                  EzizaColors.kPurpleD),
              _hfDiv(),
              _hfStat('${_openDeliveries.length}', 'Available',
                  const Color(0xFF0284C7)),
              _hfDiv(),
              _hfStat('$completed', 'Completed', EzizaColors.kSuccess),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _riderHomeHdr() {
    final firstName = _rider?.fullName.trim().split(' ').first ?? '';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
        boxShadow: [BoxShadow(
            color: Color(0x556C3483), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(right: -22, top: 6,
              child: Container(width: 150, height: 150,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: const Color(0xFF7E57C2).withValues(alpha: 0.13)))),
          Positioned(left: -16, bottom: 10,
              child: Container(width: 80, height: 80,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: EzizaColors.kGold.withValues(alpha: 0.07)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 64),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('EZIZA',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                        color: Colors.white38, letterSpacing: 2.5)),
                const SizedBox(height: 4),
                Text(
                  firstName.isNotEmpty ? 'Hello, $firstName! 👋' : 'Hello! 👋',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -0.3),
                ),
                const SizedBox(height: 3),
                Text(
                  _rider?.isApproved == true
                      ? (_isOnline
                          ? "You're online — ready for deliveries."
                          : "You're offline.")
                      : 'Your account is pending approval.',
                  style: const TextStyle(fontSize: 13, color: Colors.white60),
                ),
              ])),
              if (_rider?.isApproved == true)
                _toggling
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: EzizaColors.kWhite))
                    : GestureDetector(
                        onTap: _toggleOnline,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isOnline
                                ? const Color(0xFF16A34A)
                                : Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: _isOnline
                                    ? Colors.transparent
                                    : Colors.white.withValues(alpha: 0.18)),
                            boxShadow: _isOnline
                                ? [BoxShadow(
                                    color: const Color(0xFF16A34A)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3))]
                                : null,
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 7, height: 7,
                                decoration: BoxDecoration(
                                    color: _isOnline
                                        ? EzizaColors.kWhite
                                        : Colors.white54,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(_isOnline ? 'Online' : 'Offline',
                                style: const TextStyle(
                                    color: EzizaColors.kWhite,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _rideCta() => GestureDetector(
    onTap: () => setState(() => _tab = 1),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
            color: EzizaColors.kPurpleD.withValues(alpha: 0.35),
            blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _isOnline ? Icons.work_rounded : Icons.power_settings_new_rounded,
            color: EzizaColors.kGold, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(
            _isOnline
                ? '${_openDeliveries.length} Jobs Available'
                : 'Go Online to Find Jobs',
            style: const TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            _isOnline
                ? 'Tap to browse and place bids'
                : 'Toggle online to start receiving requests',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded,
            color: Colors.white38, size: 14),
      ]),
    ),
  );

  Widget _homeSectionLabel(String title, IconData icon, Color color) =>
      Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: EzizaColors.kText, letterSpacing: 0.1)),
      ]);

  Widget _homeViewAllBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: EzizaColors.kPurpleD,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        const Icon(Icons.arrow_forward_rounded,
            size: 14, color: EzizaColors.kPurpleD),
      ]),
    ),
  );

  Widget _homeEmptyDeliveries() => Container(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
        color: EzizaColors.kWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EzizaColors.kBorder)),
    child: Column(children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: EzizaColors.kPurple.withValues(alpha: 0.08),
            shape: BoxShape.circle),
        child: const Icon(Icons.local_shipping_outlined,
            size: 32, color: EzizaColors.kPurple),
      ),
      const SizedBox(height: 14),
      const Text('No Active Deliveries',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              color: EzizaColors.kText)),
      const SizedBox(height: 6),
      const Text('Go online and browse jobs to start earning.',
          style: TextStyle(fontSize: 12, color: EzizaColors.kMuted, height: 1.4),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _hfStat(String value, String label, Color color) => Expanded(
    child: Column(children: [
      Text(value,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
              color: color, height: 1)),
      const SizedBox(height: 5),
      Text(label,
          style: const TextStyle(fontSize: 10, color: EzizaColors.kMuted,
              fontWeight: FontWeight.w600, height: 1.3),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _hfDiv() => Container(
    width: 1, height: 34, color: EzizaColors.kBorder,
    margin: const EdgeInsets.symmetric(horizontal: 4));

  // ── Jobs tab helpers ──────────────────────────────────────────

  Widget _jMiniStat(String value, String label, Color color) => Expanded(
    child: Column(children: [
      Text(value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
              color: color, height: 1)),
      const SizedBox(height: 3),
      Text(label,
          style: TextStyle(fontSize: 9,
              color: Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _jMiniStatDiv() => Container(
    width: 1, height: 24, color: Colors.white.withValues(alpha: 0.15),
    margin: const EdgeInsets.symmetric(horizontal: 2));

  Widget _jTabBadge(String count, Color color, {bool dark = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: 0.2)
          : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(count,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
            color: color)),
  );

  Widget _tabHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) =>
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: EzizaColors.kPurpleD.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(right: -24, top: 6,
                child: Container(width: 130, height: 130,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: EzizaColors.kPurple.withValues(alpha: 0.12)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('EZIZA',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                            color: Colors.white38, letterSpacing: 2.5)),
                    const SizedBox(height: 6),
                    Text(title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.3)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 13, color: Colors.white60)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Icon(icon, color: Colors.white70, size: 20),
                ),
              ]),
            ),
          ]),
        ),
      );

  // ── Tab views ─────────────────────────────────────────────────

  Widget _homeTab() {
    final approved = _rider?.isApproved == true;
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: EzizaColors.kPurpleD));
    }
    return RefreshIndicator(
      color: EzizaColors.kPurpleD,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _riderHeaderWithStats()),
          SliverPadding(
            // 76 = 52px card overhang + 24px gap
            padding: const EdgeInsets.fromLTRB(20, 76, 20, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _rideCta(),
                const SizedBox(height: 32),
                if (_rider != null && !approved) ...[
                  _statusExplanation(),
                  const SizedBox(height: 32),
                ],
                if (approved) ...[
                  if (_pendingInvites.isNotEmpty) ...[
                    _homeSectionLabel('Company Invites',
                        Icons.mail_outline_rounded, EzizaColors.kGold),
                    const SizedBox(height: 14),
                    ..._pendingInvites.map(_inviteCard),
                    const SizedBox(height: 32),
                  ],
                  _homeSectionLabel('Active Deliveries',
                      Icons.local_shipping_rounded, EzizaColors.kPurpleD),
                  const SizedBox(height: 14),
                  if (_activeDeliveries.isEmpty)
                    _homeEmptyDeliveries()
                  else ...[
                    ..._activeDeliveries.take(3).map(_activeDeliveryCard),
                    if (_activeDeliveries.length > 3)
                      _homeViewAllBtn(
                          '${_activeDeliveries.length - 3} more active',
                          () => setState(() => _tab = 1)),
                  ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobsTab() {
    final approved = _rider?.isApproved == true;
    final activeCount  = _activeDeliveries.length + _openDeliveries.length;
    final historyCount = _jobHistory.length;

    return Column(children: [
      // ── Header with frosted stats + inner TabBar ────────────
      Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
          boxShadow: [BoxShadow(
              color: Color(0x556C3483), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(right: -20, top: 8,
                child: Container(width: 130, height: 130,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: const Color(0xFF7E57C2).withValues(alpha: 0.13)))),
            Positioned(left: -14, bottom: 30,
                child: Container(width: 70, height: 70,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: EzizaColors.kGold.withValues(alpha: 0.07)))),
            Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('EZIZA',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                          color: Colors.white38, letterSpacing: 2.5)),
                  const SizedBox(height: 6),
                  const Text('Jobs',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.3)),
                  const SizedBox(height: 3),
                  Text(
                    approved
                        ? _isCompanyRider
                            ? '${_activeDeliveries.length} active · ${_jobHistory.length} completed'
                            : '${_openDeliveries.length} available · ${_jobHistory.length} completed'
                        : 'Account approval required',
                    style: const TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Row(children: [
                      _jMiniStat('${_activeDeliveries.length}', 'In Progress',
                          EzizaColors.kGold),
                      _jMiniStatDiv(),
                      if (!_isCompanyRider)
                        _jMiniStat('${_openDeliveries.length}', 'Available',
                            Colors.white),
                      if (_isCompanyRider)
                        _jMiniStat('${_activeDeliveries.length}', 'Active',
                            Colors.white),
                      _jMiniStatDiv(),
                      _jMiniStat('$historyCount', 'Completed',
                          const Color(0xFF4ADE80)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _jobsTabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                indicatorColor: EzizaColors.kGold,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.white.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                tabs: [
                  Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Active'),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 6),
                      _jTabBadge('$activeCount', Colors.white, dark: true),
                    ],
                  ])),
                  Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('History'),
                    if (historyCount > 0) ...[
                      const SizedBox(width: 6),
                      _jTabBadge('$historyCount', Colors.white54),
                    ],
                  ])),
                  const Tab(text: 'Rating'),
                ],
              ),
            ]),
          ]),
        ),
      ),

      // ── Tab views ──────────────────────────────────────────
      Expanded(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
            : !approved
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                            color: Color(0xFFF3E5F5), shape: BoxShape.circle),
                        child: const Icon(Icons.lock_outline_rounded,
                            size: 40, color: EzizaColors.kPurple)),
                    const SizedBox(height: 16),
                    const Text('Approval Required',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 16, color: EzizaColors.kText)),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                          'Your rider account must be approved before you can see jobs.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: EzizaColors.kMuted, fontSize: 13, height: 1.4)),
                    ),
                  ]))
                : TabBarView(
                    controller: _jobsTabController,
                    children: [
                      // ── Active tab: in-progress + available to bid ──
                      RefreshIndicator(
                        color: EzizaColors.kPurpleD,
                        onRefresh: _load,
                        child: _activeDeliveries.isEmpty && (_isCompanyRider || _openDeliveries.isEmpty)
                            ? Center(
                                child: SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: EzizaColors.kPurpleD
                                              .withValues(alpha: 0.07),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.inbox_rounded,
                                            size: 48,
                                            color: EzizaColors.kPurpleD
                                                .withValues(alpha: 0.45)),
                                      ),
                                      const SizedBox(height: 20),
                                      const Text('No Active Jobs',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 18,
                                              color: EzizaColors.kText),
                                          textAlign: TextAlign.center),
                                      const SizedBox(height: 8),
                                      Text(
                                          _riderLat != null
                                              ? 'No jobs in your area right now. Check back soon.'
                                              : 'Go online to start receiving job requests.',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: EzizaColors.kMuted,
                                              fontSize: 13,
                                              height: 1.4)),
                                    ],
                                  ),
                                ),
                              )
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 60),
                                children: [
                                  if (_activeDeliveries.isNotEmpty) ...[
                                    _sectionHeader('In Progress',
                                        Icons.local_shipping_rounded,
                                        EzizaColors.kPurpleD,
                                        badge: '${_activeDeliveries.length}'),
                                    const SizedBox(height: 12),
                                    ..._activeDeliveries.map(_activeDeliveryCard),
                                    const SizedBox(height: 24),
                                  ],
                                  if (!_isCompanyRider) ...[
                                    _sectionHeader('Available to Bid',
                                        Icons.inbox_rounded,
                                        const Color(0xFF0284C7),
                                        badge: _openDeliveries.isNotEmpty
                                            ? '${_openDeliveries.length}'
                                            : null),
                                    const SizedBox(height: 12),
                                    if (_openDeliveries.isEmpty)
                                      _emptyRequests(),
                                    ..._openDeliveries.map(_deliveryCard),
                                  ],
                                ],
                              ),
                      ),
                      // ── History tab ────────────────────────────────
                      RefreshIndicator(
                        color: EzizaColors.kPurpleD,
                        onRefresh: _load,
                        child: _jobHistory.isEmpty
                            ? Center(
                                child: SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: EzizaColors.kPurpleD
                                              .withValues(alpha: 0.07),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.history_rounded,
                                            size: 48,
                                            color: EzizaColors.kPurpleD
                                                .withValues(alpha: 0.45)),
                                      ),
                                      const SizedBox(height: 20),
                                      const Text('No Job History',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 18,
                                              color: EzizaColors.kText),
                                          textAlign: TextAlign.center),
                                      const SizedBox(height: 8),
                                      const Text(
                                          'Completed deliveries will appear here.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: EzizaColors.kMuted,
                                              fontSize: 13,
                                              height: 1.4)),
                                    ],
                                  ),
                                ),
                              )
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 60),
                                children:
                                    _jobHistory.map(_jobHistoryCard).toList(),
                              ),
                      ),
                      // ── Rating tab ──────────────────────────────────
                      RefreshIndicator(
                        color: EzizaColors.kPurpleD,
                        onRefresh: _load,
                        child: _ratingSubTab(),
                      ),
                    ],
                  ),
      ),
    ]);
  }

  Widget _ratingSubTab() {
    final avg = _rider?.ratingAvg ?? 0.0;

    if (avg <= 0) {
      return earningsEmptyState(
          Icons.star_outline_rounded,
          'No Ratings Yet',
          'Ratings from customers will appear here once you complete deliveries.');
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: EzizaColors.kWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: EzizaColors.kBorder)),
          child: Column(children: [
            Text(avg.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: EzizaColors.kText)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < avg.round();
                return Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: EzizaColors.kGold,
                    size: 26);
              }),
            ),
            const SizedBox(height: 10),
            Text('Average rating from completed deliveries',
                style: const TextStyle(
                    fontSize: 13, color: EzizaColors.kMuted),
                textAlign: TextAlign.center),
          ]),
        ),
        if (_myRatings.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Recent Reviews',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: EzizaColors.kText)),
          const SizedBox(height: 12),
          ..._myRatings.map(_myRatingCard),
        ],
      ],
    );
  }

  Widget _myRatingCard(Map<String, dynamic> r) {
    final rating  = (r['rating'] as num?)?.toInt() ?? 0;
    final role    = r['rater_role'] as String? ?? '';
    final name    = (r['rater_name'] as String?)?.trim();
    final comment = r['comment'] as String?;
    final date    = r['created_at'] as String? ?? '';
    final dateLabel = date.length >= 10 ? date.substring(0, 10) : date;
    final roleLabel = role == 'sender' ? 'Sender' : 'Receiver';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EzizaColors.kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  (name == null || name.isEmpty) ? 'Anonymous' : name,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: EzizaColors.kText)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: EzizaColors.kPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(roleLabel,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: EzizaColors.kPurpleD)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: List.generate(
              5,
              (i) => Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: EzizaColors.kGold,
                  size: 18))),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment,
                style: const TextStyle(fontSize: 13, color: EzizaColors.kText)),
          ],
          const SizedBox(height: 6),
          Text(dateLabel,
              style: const TextStyle(fontSize: 11, color: EzizaColors.kMuted)),
        ],
      ),
    );
  }

  Widget _earningsTab() {
    final approved = _rider?.isApproved == true;
    return Column(children: [
      _tabHeader(
        title: 'Earnings',
        subtitle: approved
            ? 'Balance & payout requests'
            : 'Account approval required',
        icon: Icons.account_balance_wallet_rounded,
      ),
      Expanded(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
            : !approved
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                              color: Color(0xFFF3E5F5), shape: BoxShape.circle),
                          child: const Icon(Icons.account_balance_wallet_outlined,
                              size: 40, color: EzizaColors.kPurple)),
                      const SizedBox(height: 16),
                      const Text('Earnings Locked',
                          style: TextStyle(fontWeight: FontWeight.w700,
                              fontSize: 16, color: EzizaColors.kText)),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                            'Earnings are available once your account is approved.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: EzizaColors.kMuted, fontSize: 13, height: 1.4)),
                      ),
                    ]),
                  )
                : _earningsTabBody(),
      ),
    ]);
  }

  Widget _earningsTabBody() {
    final earningsHistory = _jobHistory; // already status='confirmed' only

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: _walletCard(),
      ),
      const SizedBox(height: 4),
      TabBar(
        controller: _earningsTabController,
        labelColor: EzizaColors.kPurpleD,
        unselectedLabelColor: EzizaColors.kMuted,
        labelStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500, fontSize: 13),
        indicatorColor: EzizaColors.kPurpleD,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: [
          Tab(text: 'Earnings (${earningsHistory.length})'),
          Tab(text: 'Payouts (${_payoutHistory.length})'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _earningsTabController,
          children: [
            RefreshIndicator(
              color: EzizaColors.kPurpleD,
              onRefresh: _load,
              child: earningsHistory.isEmpty
                  ? earningsEmptyState(
                      Icons.receipt_long_outlined,
                      'No Earnings Yet',
                      'Completed deliveries will show their earnings breakdown here.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: earningsHistory.length,
                      itemBuilder: (_, i) =>
                          earningsHistoryCard(earningsHistory[i]),
                    ),
            ),
            RefreshIndicator(
              color: EzizaColors.kPurpleD,
              onRefresh: _load,
              child: _payoutHistory.isEmpty
                  ? earningsEmptyState(
                      Icons.account_balance_outlined,
                      'No Payout Requests',
                      'Requests you submit will show their status here.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _payoutHistory.length,
                      itemBuilder: (_, i) =>
                          payoutHistoryCard(_payoutHistory[i]),
                    ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _heroDivider() => Container(
      width: 1, height: 32, color: Colors.white.withValues(alpha: 0.15));

  // ── Status explanation ────────────────────────────────────────

  Widget _statusExplanation() {
    final status = _rider?.status ?? 'pending';
    final msg = switch (status) {
      'pending'  => "Your application is under review. We'll notify you once approved.",
      'rejected' => 'Your application was not successful. Contact support for more information.',
      'suspended'=> 'Your account is currently suspended. Contact support to resolve this.',
      _          => 'Unknown status. Please contact support.',
    };
    final (Color color, Color bg, IconData icon) = switch (status) {
      'rejected'  => (EzizaColors.kError,  const Color(0xFFFFEDED), Icons.cancel_outlined),
      'suspended' => (Colors.orange,        const Color(0xFFFFF3E0), Icons.pause_circle_outline_rounded),
      _           => (EzizaColors.kGold,   const Color(0xFFFFF8E1), Icons.hourglass_top_rounded),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: color),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: color.withValues(alpha: 0.25))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 16)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Account Status', style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: color)),
                  const SizedBox(height: 4),
                  Text(msg, style: TextStyle(fontSize: 12, color: color, height: 1.4)),
                ])),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Invite card ───────────────────────────────────────────────

  Widget _inviteCard(Map<String, dynamic> invite) {
    final companyName =
        (invite['company'] as Map?)?['name'] ?? 'A logistics company';
    final inviteId = invite['id'] as int;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EzizaColors.kGold.withValues(alpha: 0.35)),
            boxShadow: [BoxShadow(color: EzizaColors.kGold.withValues(alpha: 0.1),
                blurRadius: 10, offset: const Offset(0, 3))]),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [EzizaColors.kGold, Color(0xFFD97706)],
                        begin: Alignment.topCenter, end: Alignment.bottomCenter))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: EzizaColors.kGold.withValues(alpha: 0.1),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.business_rounded,
                            size: 16, color: EzizaColors.kGold)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(companyName,
                        style: const TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 14, color: EzizaColors.kText))),
                  ]),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.only(left: 42),
                    child: Text('Invited you to join their delivery team',
                        style: TextStyle(fontSize: 12, color: EzizaColors.kMuted)),
                  ),
                  const SizedBox(height: 12),
                  _inviteLoading
                      ? const Center(child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              color: EzizaColors.kPurpleD)))
                      : Row(children: [
                          Expanded(child: GestureDetector(
                            onTap: () => _respondInvite(inviteId, false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(color: EzizaColors.kSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: EzizaColors.kBorder)),
                              child: const Center(child: Text('Decline',
                                  style: TextStyle(fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: EzizaColors.kMuted))),
                            ),
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: GestureDetector(
                            onTap: () => _respondInvite(inviteId, true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    EzizaColors.kPurple, EzizaColors.kPurpleD]),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [BoxShadow(
                                      color: EzizaColors.kPurpleD.withValues(alpha: 0.25),
                                      blurRadius: 8, offset: const Offset(0, 3))]),
                              child: const Center(child: Text('Accept',
                                  style: TextStyle(fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: EzizaColors.kWhite))),
                            ),
                          )),
                        ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Active delivery card ──────────────────────────────────────

  Widget _activeDeliveryCard(Map<String, dynamic> d) {
    final status            = d['status'] as String? ?? 'assigned';
    final isPickedUp        = status == 'picked_up';
    final isAwaitingHandoff = status == 'awaiting_pickup_confirm';
    final isDelivered       = status == 'delivered';
    final deliveryId        = d['id'] as String;
    final fee               = (d['agreed_price'] as num?)?.toDouble();

    final (Color accentColor, Color chipText, Color chipBg, String chipLabel) =
        switch (status) {
      'delivered'               => (EzizaColors.kSuccess, EzizaColors.kSuccess,
                                    const Color(0xFFDCFCE7), 'Delivered'),
      'picked_up'               => (const Color(0xFF0284C7), const Color(0xFF0284C7),
                                    const Color(0xFFE0F2FE), 'In Transit'),
      'awaiting_pickup_confirm' => (EzizaColors.kGold, const Color(0xFF92400E),
                                    const Color(0xFFFFF8E1), 'At Pickup'),
      _                         => (EzizaColors.kPurpleD, EzizaColors.kPurpleD,
                                    const Color(0xFFF3E5F5), 'Assigned'),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.25)),
            boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.08),
                blurRadius: 12, offset: const Offset(0, 4))]),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Header row
                  Row(children: [
                    Expanded(child: Row(children: [
                      Icon(Icons.radio_button_checked_rounded,
                          size: 12, color: EzizaColors.kPurpleD),
                      const SizedBox(width: 4),
                      Flexible(child: Text('${d['pickup_address'] ?? '—'}',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700, color: EzizaColors.kText),
                          overflow: TextOverflow.ellipsis)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 11, color: EzizaColors.kMuted)),
                      Icon(Icons.location_on_rounded, size: 12, color: EzizaColors.kGold),
                      const SizedBox(width: 4),
                      Flexible(child: Text('${d['delivery_address'] ?? '—'}',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700, color: EzizaColors.kText),
                          overflow: TextOverflow.ellipsis)),
                    ])),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: chipBg,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(chipLabel, style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w800, color: chipText)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Address boxes
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: EzizaColors.kPurple.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: EzizaColors.kPurple.withValues(alpha: 0.15))),
                    child: Row(children: [
                      const Icon(Icons.store_rounded,
                          size: 13, color: EzizaColors.kPurpleD),
                      const SizedBox(width: 8),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('PICKUP', style: TextStyle(fontSize: 9,
                            color: EzizaColors.kPurpleD,
                            fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        Text('${d['pickup_address'] ?? '—'}',
                            style: const TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600, color: EzizaColors.kText,
                                height: 1.3),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (d['pickup_contact_name'] != null ||
                            d['pickup_contact_phone'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${d['pickup_contact_name'] ?? ''} ${d['pickup_contact_phone'] ?? ''}'.trim(),
                            style: const TextStyle(fontSize: 10, color: EzizaColors.kMuted),
                          ),
                        ],
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: EzizaColors.kGold.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: EzizaColors.kGold.withValues(alpha: 0.2))),
                    child: Row(children: [
                      const Icon(Icons.home_rounded,
                          size: 13, color: EzizaColors.kGold),
                      const SizedBox(width: 8),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('DROP-OFF', style: TextStyle(fontSize: 9,
                            color: EzizaColors.kGold,
                            fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        Text('${d['delivery_address'] ?? '—'}',
                            style: const TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600, color: EzizaColors.kText,
                                height: 1.3),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                    ]),
                  ),
                  if (fee != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: EzizaColors.kSuccess.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: EzizaColors.kSuccess.withValues(alpha: 0.2)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.payments_rounded,
                              size: 12, color: EzizaColors.kSuccess),
                          const SizedBox(width: 5),
                          Text('₦${fee.toStringAsFixed(0)}  ·  Earning',
                              style: const TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: EzizaColors.kSuccess)),
                        ]),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  // Action area
                  if (_actionLoading)
                    const Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: EzizaColors.kPurpleD)))
                  else if (isDelivered)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: EzizaColors.kSuccess.withValues(alpha: 0.3)),
                      ),
                      child: const Row(children: [
                        SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2,
                                color: EzizaColors.kSuccess)),
                        SizedBox(width: 10),
                        Expanded(child: Text(
                            'Package delivered — waiting for customer to confirm receipt…',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: Color(0xFF166534)))),
                      ]),
                    )
                  else if (isPickedUp) ...[
                    _actionBtn(
                      label: 'Mark Delivered',
                      icon: Icons.check_circle_outline_rounded,
                      gradient: [const Color(0xFF16A34A), const Color(0xFF15803D)],
                      glowColor: const Color(0xFF16A34A),
                      onTap: () => _markStatus(deliveryId, 'delivered'),
                    ),
                    const SizedBox(height: 8),
                    _viewRouteBtn(d),
                  ] else if (isAwaitingHandoff)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: EzizaColors.kGold.withValues(alpha: 0.4)),
                      ),
                      child: const Row(children: [
                        SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2,
                                color: Color(0xFFD97706))),
                        SizedBox(width: 10),
                        Expanded(child: Text(
                            'Waiting for merchant to confirm handoff…',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E)))),
                      ]),
                    )
                  else ...[
                    _actionBtn(
                      label: "I'm at Pickup — Notify Merchant",
                      icon: Icons.store_rounded,
                      gradient: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                      glowColor: EzizaColors.kPurpleD,
                      onTap: () => _markStatus(deliveryId, 'awaiting_pickup_confirm'),
                    ),
                    const SizedBox(height: 8),
                    _viewRouteBtn(d),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _viewRouteBtn(Map<String, dynamic> d) => GestureDetector(
    onTap: () async {
      await Get.to(() => RiderMapPage(delivery: d, riderId: _rider!.id));
      _load();
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(color: EzizaColors.kNavy,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: EzizaColors.kNavy.withValues(alpha: 0.35),
              blurRadius: 8, offset: const Offset(0, 3))]),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.map_rounded, size: 15, color: EzizaColors.kGold),
        SizedBox(width: 7),
        Text('View Route on Map', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700, color: EzizaColors.kWhite)),
      ]),
    ),
  );

  // ── Job board card ────────────────────────────────────────────

  Widget _deliveryCard(Map<String, dynamic> d) {
    final dist = _pickupDistance(d);
    return GestureDetector(
      onTap: () => _showBidSheet(d),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
              color: EzizaColors.kWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EzizaColors.kBorder),
              boxShadow: [BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.05),
                  blurRadius: 8, offset: const Offset(0, 3))]),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4,
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                          begin: Alignment.topCenter, end: Alignment.bottomCenter))),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Route
                    Row(children: [
                      const Icon(Icons.radio_button_checked_rounded,
                          size: 12, color: EzizaColors.kPurpleD),
                      const SizedBox(width: 4),
                      Flexible(child: Text('${d['pickup_address'] ?? '—'}',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700, color: EzizaColors.kText),
                          overflow: TextOverflow.ellipsis)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 11, color: EzizaColors.kMuted)),
                      const Icon(Icons.location_on_rounded,
                          size: 12, color: EzizaColors.kGold),
                      const SizedBox(width: 4),
                      Flexible(child: Text('${d['delivery_address'] ?? '—'}',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700, color: EzizaColors.kText),
                          overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 8),
                    // Meta pills
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _metaPill(Icons.access_time_rounded,
                          _ago(d['created_at'] as String?), EzizaColors.kMuted),
                      if (dist != null)
                        _metaPill(Icons.near_me_rounded,
                          dist < 1
                              ? '${(dist * 1000).round()} m'
                              : '${dist.toStringAsFixed(1)} km away',
                          EzizaColors.kGold),
                      if (d['pickup_state'] != null)
                        _metaPill(Icons.location_city_rounded,
                            d['pickup_state'] as String, EzizaColors.kNavy),
                    ]),
                    if (d['package_description'] != null &&
                        (d['package_description'] as String).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(d['package_description'] as String,
                          style: const TextStyle(fontSize: 12, color: EzizaColors.kMuted,
                              fontStyle: FontStyle.italic, height: 1.3),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(
                              color: EzizaColors.kPurpleD.withValues(alpha: 0.25),
                              blurRadius: 8, offset: const Offset(0, 3))]),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.gavel_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Place a Bid', style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800, color: Colors.white)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _metaPill(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 10, color: color,
          fontWeight: FontWeight.w600)),
    ]),
  );

  // ── Job history card ──────────────────────────────────────────

  Widget _jobHistoryCard(Map<String, dynamic> d) {
    final fee = (d['agreed_price'] as num?)?.toDouble() ?? 0;
    final createdAt = d['created_at'] != null
        ? DateTime.tryParse(d['created_at'].toString())?.toLocal()
        : null;
    String dateLabel = '';
    if (createdAt != null) {
      final diff = DateTime.now().difference(createdAt);
      if (diff.inDays == 0) {
        dateLabel = 'Today';
      } else if (diff.inDays == 1) {
        dateLabel = 'Yesterday';
      } else {
        dateLabel = '${createdAt.day}/${createdAt.month}/${createdAt.year}';
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2))]),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: EzizaColors.kSuccess.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded,
                color: EzizaColors.kSuccess, size: 16)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d['pickup_address'] ?? '—'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: EzizaColors.kText),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.arrow_forward_rounded,
                size: 10, color: EzizaColors.kMuted),
            const SizedBox(width: 3),
            Expanded(child: Text('${d['delivery_address'] ?? '—'}',
                style: const TextStyle(fontSize: 11, color: EzizaColors.kMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          if (dateLabel.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(dateLabel,
                style: const TextStyle(fontSize: 10, color: EzizaColors.kMuted)),
          ],
        ])),
        if (fee > 0)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₦${fee.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                    color: EzizaColors.kSuccess)),
            const Text('earned',
                style: TextStyle(fontSize: 9, color: EzizaColors.kMuted)),
          ]),
      ]),
    );
  }

  // ── Wallet card ───────────────────────────────────────────────

  Widget _walletCard() {
    final balance        = _rider?.walletBalance ?? 0.0;
    final hasBankDetails = _rider?.accountNumber != null;
    final pendingPayout  = _payoutHistory
        .where((p) => ['pending', 'approved'].contains(p['status']))
        .fold<double>(0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));
    final hasPending     = pendingPayout > 0;
    final available      = (balance - pendingPayout).clamp(0, double.infinity);
    final totalEarned    = _jobHistory.fold<double>(
        0, (sum, d) => sum + ((d['agreed_price'] as num?)?.toDouble() ?? 0));

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.35),
              blurRadius: 16, offset: const Offset(0, 6))]),
      child: Stack(children: [
        Positioned(right: -20, top: -20,
            child: Container(width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: EzizaColors.kPurple.withValues(alpha: 0.15)))),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Available Balance',
                style: TextStyle(fontSize: 11, color: Colors.white54,
                    fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Text(
              '₦${available.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900,
                  color: EzizaColors.kWhite, letterSpacing: -1.5),
            ),
            if (hasPending) ...[
              const SizedBox(height: 4),
              Text(
                '₦${pendingPayout.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')} held for pending payout',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
            const SizedBox(height: 16),
            // Stats row
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
              child: Row(children: [
                _walletStat('${_rider?.totalDeliveries ?? 0}', 'Deliveries'),
                _heroDivider(),
                _walletStat(
                  (_rider?.ratingAvg ?? 0) > 0
                      ? _rider!.ratingAvg.toStringAsFixed(1)
                      : '—',
                  'Rating',
                  suffix: (_rider?.ratingAvg ?? 0) > 0 ? ' ⭐' : '',
                ),
                _heroDivider(),
                _walletStat(
                  '₦${totalEarned.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}',
                  'Total Earned',
                ),
              ]),
            ),
            const SizedBox(height: 14),
            hasPending
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                        color: EzizaColors.kGold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: EzizaColors.kGold.withValues(alpha: 0.4))),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.hourglass_top_rounded,
                          color: EzizaColors.kGold, size: 15),
                      SizedBox(width: 7),
                      Text('Payout Requested — Awaiting Approval',
                          style: TextStyle(color: EzizaColors.kGold,
                              fontWeight: FontWeight.w700, fontSize: 12)),
                    ]),
                  )
                : GestureDetector(
                    onTap: hasBankDetails
                        ? _showPayoutSheet
                        : () => Get.to(() => const BankAccountPage(role: BankAccountRole.rider)),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2))),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.account_balance_rounded,
                            color: EzizaColors.kWhite, size: 16),
                        SizedBox(width: 8),
                        Text('Request Payout',
                            style: TextStyle(color: EzizaColors.kWhite,
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ]),
                    ),
                  ),
          ]),
        ),
      ]),
    );
  }

  Widget _walletStat(String value, String label, {String suffix = ''}) =>
      Expanded(child: Column(children: [
        Text('$value$suffix',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: EzizaColors.kWhite),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white54,
                fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ]));

  // ── Account tab ───────────────────────────────────────────────

  Widget _accountTab() {
    final rider   = _rider;
    if (rider == null) {
      return const Center(
          child: CircularProgressIndicator(color: EzizaColors.kPurpleD));
    }
    final initials = rider.fullName.trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final email = rider.email ?? _db.auth.currentUser?.email ?? '';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _riderAccountHero(rider, initials, email),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── ACCOUNT ────────────────────────────────
                _acctSectionLabel('Account'),
                const SizedBox(height: 10),
                _acctCard(children: [
                  _acctTile(
                    icon: Icons.badge_outlined,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Edit Profile',
                    subtitle: 'Personal info & vehicle',
                    onTap: () => Get.to(() => const ProfilePage()),
                  ),
                  _acctDivider(),
                  _acctTile(
                    icon: Icons.account_balance_outlined,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Bank Account',
                    subtitle: rider.accountNumber != null
                        ? '${rider.bankName ?? ''} · ${rider.accountNumber}'
                        : 'Not set up yet',
                    onTap: () => Get.to(() => const BankAccountPage(role: BankAccountRole.rider)),
                  ),
                  _acctDivider(),
                  _acctTile(
                    icon: Icons.lock_outline_rounded,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Change Password',
                    onTap: () => Get.to(() => const ChangePasswordPage()),
                  ),
                  if (!_isCompanyRider) ...[
                    _acctDivider(),
                    _acctTile(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: EzizaColors.kSuccess,
                      iconBg: EzizaColors.kSuccess.withValues(alpha: 0.1),
                      title: 'Earnings & Payouts',
                      subtitle: '₦${rider.walletBalance.toStringAsFixed(0)} available',
                      onTap: () => setState(() => _tab = 2),
                    ),
                  ],
                ]),
                const SizedBox(height: 20),

                // ── STATS ───────────────────────────────────
                _acctSectionLabel('Stats'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                  decoration: BoxDecoration(
                    color: EzizaColors.kWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EzizaColors.kBorder),
                    boxShadow: [
                      BoxShadow(
                          color: EzizaColors.kPurple.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: Row(children: [
                    _acctStatCell('${rider.totalDeliveries}', 'Deliveries',
                        EzizaColors.kPurpleD),
                    _acctVertDiv(),
                    _acctStatCell(
                      rider.ratingAvg > 0
                          ? rider.ratingAvg.toStringAsFixed(1)
                          : '—',
                      'Rating',
                      EzizaColors.kGold,
                    ),
                    _acctVertDiv(),
                    _acctStatCell('${_activeDeliveries.length}', 'Active',
                        const Color(0xFF0284C7)),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── VEHICLE ─────────────────────────────────
                _acctSectionLabel('Vehicle'),
                const SizedBox(height: 10),
                _acctCard(children: [
                  _acctTile(
                    icon: Icons.two_wheeler_rounded,
                    iconColor: EzizaColors.kNavy,
                    iconBg: EzizaColors.kNavy.withValues(alpha: 0.08),
                    title: rider.vehicleType[0].toUpperCase() +
                        rider.vehicleType.substring(1),
                    subtitle: rider.vehiclePlate?.isNotEmpty == true
                        ? 'Plate: ${rider.vehiclePlate}'
                        : 'No plate registered',
                    onTap: () => Get.to(() => const ProfilePage()),
                    showTrailing: false,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── SUPPORT ─────────────────────────────────
                _acctSectionLabel('Support'),
                const SizedBox(height: 10),
                _acctCard(children: [
                  _acctTile(
                    icon: Icons.support_agent_outlined,
                    iconColor: Colors.blueGrey,
                    iconBg: Colors.blueGrey.shade50,
                    title: 'Help & Support',
                    subtitle: 'Open a support ticket',
                    onTap: () => Get.to(() => const SupportTicketsPage()),
                  ),
                  _acctDivider(),
                  _acctTile(
                    icon: Icons.phone_outlined,
                    iconColor: Colors.blueGrey,
                    iconBg: Colors.blueGrey.shade50,
                    title: 'Phone',
                    subtitle: rider.phone.isNotEmpty ? rider.phone : 'Not set',
                    onTap: () {},
                    showTrailing: false,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── SIGN OUT ────────────────────────────────
                _acctCard(children: [
                  _acctTile(
                    icon: Icons.logout_rounded,
                    iconColor: EzizaColors.kError,
                    iconBg: EzizaColors.kError.withValues(alpha: 0.08),
                    title: 'Sign Out',
                    titleColor: EzizaColors.kError,
                    showTrailing: false,
                    onTap: _confirmSignOut,
                  ),
                ]),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Rider account hero header ─────────────────────────────────

  Widget _riderAccountHero(Rider rider, String initials, String email) {
    final (Color sColor, Color sBg) = switch (rider.status) {
      'approved'  => (EzizaColors.kSuccess,      const Color(0xFFDCFCE7)),
      'rejected'  => (EzizaColors.kError,         const Color(0xFFFFEBEE)),
      'suspended' => (Colors.orange,               const Color(0xFFFFF3E0)),
      _           => (EzizaColors.kGold,           const Color(0xFFFFF8E1)),
    };
    final statusLabel = rider.status[0].toUpperCase() + rider.status.substring(1);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(color: Color(0x446C3483), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(right: -22, top: 10,
              child: Container(width: 140, height: 140,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: EzizaColors.kPurple.withValues(alpha: 0.13)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('EZIZA',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                        color: Colors.white38, letterSpacing: 2.5)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: sBg.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(color: sColor, fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: EzizaColors.kPurpleD.withValues(alpha: 0.4),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Center(child: Text(initials.isEmpty ? '?' : initials,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 20, fontWeight: FontWeight.w800))),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rider.fullName,
                      style: const TextStyle(color: Colors.white,
                          fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  if (email.isNotEmpty)
                    Text(email,
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.two_wheeler_rounded, size: 11, color: Colors.white54),
                    const SizedBox(width: 5),
                    Text(
                      rider.vehicleType[0].toUpperCase() + rider.vehicleType.substring(1),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    if (_isCompanyRider) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: EzizaColors.kGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: EzizaColors.kGold.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Company Rider',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                color: EzizaColors.kGold)),
                      ),
                    ],
                  ]),
                ])),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Account tab helpers ───────────────────────────────────────

  Widget _acctSectionLabel(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 2),
    child: Text(title.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: EzizaColors.kMuted, letterSpacing: 1.2)),
  );

  Widget _acctCard({required List<Widget> children}) => Container(
    decoration: BoxDecoration(
      color: EzizaColors.kWhite,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: EzizaColors.kBorder),
      boxShadow: [BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.05),
          blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(children: children),
  );

  Widget _acctTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    String? subtitle,
    Color? titleColor,
    bool showTrailing = true,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(color: iconBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 20)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                      color: titleColor ?? EzizaColors.kText)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11, color: EzizaColors.kMuted),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ])),
            if (showTrailing)
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: EzizaColors.kMuted),
          ]),
        ),
      );

  Widget _acctDivider() =>
      Divider(height: 1, indent: 70, endIndent: 16, color: Colors.grey.shade100);

  Widget _acctStatCell(String value, String label, Color color) => Expanded(
    child: Column(children: [
      Text(value,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, height: 1)),
      const SizedBox(height: 5),
      Text(label,
          style: const TextStyle(fontSize: 10, color: EzizaColors.kMuted,
              fontWeight: FontWeight.w600),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _acctVertDiv() => Container(
    width: 1, height: 36, color: EzizaColors.kBorder,
    margin: const EdgeInsets.symmetric(horizontal: 4));

  // ── Sign-out sheet ────────────────────────────────────────────

  void _confirmSignOut() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const Icon(Icons.logout_rounded, color: EzizaColors.kError, size: 36),
          const SizedBox(height: 12),
          const Text('Sign Out',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: EzizaColors.kText)),
          const SizedBox(height: 8),
          const Text('Are you sure you want to sign out?',
              style: TextStyle(fontSize: 14, color: EzizaColors.kMuted)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Get.back(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: EzizaColors.kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: EzizaColors.kBorder)),
                child: const Center(child: Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        color: EzizaColors.kText))),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () {
                Get.back();
                _auth.signOut();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: EzizaColors.kError,
                    borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('Sign Out',
                    style: TextStyle(fontWeight: FontWeight.w700,
                        color: Colors.white))),
              ),
            )),
          ]),
        ]),
      ),
    );
  }


  // ── Reusable widgets ──────────────────────────────────────────

  Widget _sectionHeader(String label, IconData icon, Color color, {String? badge}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Row(children: [
          Container(width: 4, height: 18,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(2),
              )),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800,
              fontSize: 14, color: EzizaColors.kText)),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(badge, style: const TextStyle(color: Colors.white,
                  fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      );

  Widget _emptyRequests() => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EzizaColors.kBorder)),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: EzizaColors.kPurple.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.inbox_rounded,
                  size: 32, color: EzizaColors.kPurple)),
          const SizedBox(height: 14),
          const Text('No Jobs Nearby', style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w700, color: EzizaColors.kText)),
          const SizedBox(height: 6),
          Text(
            _riderLat != null
                ? 'No pickup requests within ${_kMaxRadiusKm.round()} km of your location right now.'
                : 'Go online to see delivery requests near you.',
            style: const TextStyle(fontSize: 12, color: EzizaColors.kMuted, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ]),
      );

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required List<Color> gradient,
    required Color glowColor,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: glowColor.withValues(alpha: 0.3),
                  blurRadius: 10, offset: const Offset(0, 4))]),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
        ),
      );
}
