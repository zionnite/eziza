import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/colors.dart';

const _ngDefault = LatLng(9.0820, 8.6753);

/// Customer's live tracking view — shows rider moving on map, ETA, and
/// a "Confirm Receipt" button when the rider marks it delivered.
class DeliveryTrackingPage extends StatefulWidget {
  const DeliveryTrackingPage({
    super.key,
    required this.deliveryId,
    this.isRecipient = false,
  });
  final String deliveryId;
  final bool isRecipient;

  @override
  State<DeliveryTrackingPage> createState() => _DeliveryTrackingPageState();
}

class _DeliveryTrackingPageState extends State<DeliveryTrackingPage> {
  final _db     = Supabase.instance.client;
  final _mapCtrl = MapController();

  Map<String, dynamic>? _delivery;
  Map<String, dynamic>? _riderInfo;

  LatLng? _riderLocation;
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  List<LatLng> _routePoints = [];
  int? _etaSeconds;

  String _phase           = 'to_pickup';
  String _status          = 'loading';
  bool   _initialFit      = false;
  bool   _locationIsLive  = false;
  bool   _deliveryDone          = false;
  bool   _confirmLoading        = false;
  bool   _confirmHandoffLoading = false;
  bool   _pulse                 = false;

  RealtimeChannel? _locChannel;
  RealtimeChannel? _statusChannel;
  Timer? _pulseTimer;
  Timer? _locationPollTimer;
  String? _riderAuthUid; // stored so the poll timer can re-fetch

  @override
  void initState() {
    super.initState();
    _init();
    _pulseTimer = Timer.periodic(
        const Duration(milliseconds: 800),
        (_) { if (mounted) setState(() => _pulse = !_pulse); });
  }

  @override
  void dispose() {
    if (_locChannel   != null) _db.removeChannel(_locChannel!);
    if (_statusChannel != null) _db.removeChannel(_statusChannel!);
    _pulseTimer?.cancel();
    _locationPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _setStatus('loading');

    // ── 1. Fetch delivery ────────────────────────────────────────────────────
    try {
      final raw = await _db
          .from('deliveries')
          .select()
          .eq('id', widget.deliveryId)
          .single();
      _delivery = Map<String, dynamic>.from(raw);
    } catch (_) {
      _setStatus('no_delivery');
      return;
    }

    final d       = _delivery!;
    final dStatus = d['status'] as String? ?? 'open';
    _phase = (dStatus == 'picked_up' || dStatus == 'delivered' ||
            dStatus == 'confirmed')
        ? 'to_dropoff'
        : 'to_pickup';
    if (dStatus == 'confirmed') _deliveryDone = true;

    // ── 2. Check rider assignment (before slow geocoding) ───────────────────
    final riderRowId = d['rider_id'] as String?;
    if (riderRowId == null || ['open', 'cancelled'].contains(dStatus)) {
      _setStatus('waiting');
      _subscribeStatusChannel();
      _resolveAndApplyCoords(d); // geocode in background — no await
      return;
    }

    // ── 3. Look up rider's auth UID (fast DB call) ───────────────────────────
    String? riderAuthUid;
    try {
      final r = await _db
          .from('riders')
          .select('auth_user_id, full_name, vehicle_type, rating_avg, phone, is_available')
          .eq('id', riderRowId)
          .maybeSingle();
      if (r != null) {
        riderAuthUid = r['auth_user_id'] as String?;
        if (mounted) setState(() => _riderInfo = r);
      }
    } catch (_) {}

    if (riderAuthUid == null) {
      _setStatus('waiting');
      _subscribeStatusChannel();
      _resolveAndApplyCoords(d);
      return;
    }

    _riderAuthUid = riderAuthUid;

    // ── 4. Start realtime + poll IMMEDIATELY (before geocoding) ─────────────
    if (!_deliveryDone) {
      final ts = DateTime.now().millisecondsSinceEpoch;

      void applyLocRow(Map<String, dynamic> row) async {
        final lat = (row['latitude']  as num?)?.toDouble();
        final lng = (row['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null ||
            row['rider_id'] != riderAuthUid || !mounted) { return; }
        final hadRider = _riderLocation != null;
        setState(() {
          _riderLocation  = LatLng(lat, lng);
          _locationIsLive = true;
        });
        _checkArrival(lat, lng);
        if (!hadRider) _initialFit = false;
        if (!_initialFit) _fitMap();
        await _fetchRoute();
      }

      _locChannel = _db
          .channel('tracking_loc_${riderAuthUid}_$ts')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'rider_locations',
            filter: PostgresChangeFilter(
              type:   PostgresChangeFilterType.eq,
              column: 'rider_id',
              value:  riderAuthUid,
            ),
            callback: (p) { applyLocRow(p.newRecord); })
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'rider_locations',
            filter: PostgresChangeFilter(
              type:   PostgresChangeFilterType.eq,
              column: 'rider_id',
              value:  riderAuthUid,
            ),
            callback: (p) { applyLocRow(p.newRecord); })
          .subscribe();

      _startLocationPoll();
    }

    // ── 5. Fetch rider's current location (fast DB call) ────────────────────
    try {
      final loc = await _db
          .from('rider_locations')
          .select('latitude, longitude')
          .eq('rider_id', riderAuthUid)
          .maybeSingle();
      final rLat = (loc?['latitude']  as num?)?.toDouble();
      final rLng = (loc?['longitude'] as num?)?.toDouble();
      if (rLat != null && rLng != null && mounted) {
        setState(() {
          _riderLocation  = LatLng(rLat, rLng);
          _locationIsLive = true;
        });
        _initialFit = false;
      }
    } catch (_) {}

    _setStatus('live');

    // ── 6. Geocode pickup/dropoff in background — doesn't block location ─────
    _resolveAndApplyCoords(d);

    _subscribeStatusChannel();
  }

  // Resolves pickup/dropoff coordinates and updates map state when ready.
  // Called fire-and-forget so it never blocks location tracking setup.
  Future<void> _resolveAndApplyCoords(Map<String, dynamic> d) async {
    final pLat = (d['pickup_lat']  as num?)?.toDouble();
    final pLng = (d['pickup_lng']  as num?)?.toDouble();
    final dLat = (d['delivery_lat'] as num?)?.toDouble();
    final dLng = (d['delivery_lng'] as num?)?.toDouble();

    final resolvedPickup = (pLat != null && pLng != null)
        ? LatLng(pLat, pLng)
        : await _geocode(d['pickup_address']  as String? ?? '');
    final resolvedDropoff = (dLat != null && dLng != null)
        ? LatLng(dLat, dLng)
        : await _geocode(d['delivery_address'] as String? ?? '');

    if (!mounted) return;
    setState(() {
      _pickupLatLng  = resolvedPickup;
      _dropoffLatLng = resolvedDropoff;
    });
    // Fit map once coords land — include rider if already known
    if (!_initialFit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitMap();
      });
    }
    if (_riderLocation != null) await _fetchRoute();
  }

  // Polls rider_locations every 5 s until location is found, then backs off to 30 s.
  void _startLocationPoll() {
    _locationPollTimer?.cancel();
    _locationPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _deliveryDone || _riderAuthUid == null) {
        _locationPollTimer?.cancel();
        return;
      }
      try {
        final loc = await _db
            .from('rider_locations')
            .select('latitude, longitude')
            .eq('rider_id', _riderAuthUid!)
            .maybeSingle();
        final lat = (loc?['latitude']  as num?)?.toDouble();
        final lng = (loc?['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null && mounted) {
          final hadRider = _riderLocation != null;
          setState(() {
            _riderLocation  = LatLng(lat, lng);
            _locationIsLive = true;
          });
          _checkArrival(lat, lng);
          if (!hadRider) _initialFit = false;
          if (!_initialFit) _fitMap();
          await _fetchRoute();
          // Back off to 30-second refresh once location is established
          _locationPollTimer?.cancel();
          _locationPollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
            if (!mounted || _deliveryDone || _riderAuthUid == null) {
              _locationPollTimer?.cancel();
              return;
            }
            try {
              final r = await _db
                  .from('rider_locations')
                  .select('latitude, longitude')
                  .eq('rider_id', _riderAuthUid!)
                  .maybeSingle();
              final rlat = (r?['latitude']  as num?)?.toDouble();
              final rlng = (r?['longitude'] as num?)?.toDouble();
              if (rlat != null && rlng != null && mounted) {
                setState(() {
                  _riderLocation  = LatLng(rlat, rlng);
                  _locationIsLive = true;
                });
                _checkArrival(rlat, rlng);
                await _fetchRoute();
              }
            } catch (_) {}
          });
        }
      } catch (_) {}
    });
  }

  void _subscribeStatusChannel() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _statusChannel = _db
        .channel('tracking_status_${widget.deliveryId}_$ts')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'id',
            value:  widget.deliveryId,
          ),
          callback: (p) async {
            final row = Map<String, dynamic>.from(p.newRecord);
            if (row['id'] != widget.deliveryId || !mounted) return;
            final s = row['status'] as String? ?? '';
            setState(() {
              _delivery = {...?_delivery, ...row};
              _phase = (s == 'picked_up' || s == 'delivered' || s == 'confirmed')
                  ? 'to_dropoff'
                  : 'to_pickup';
              if (s == 'confirmed') {
                _deliveryDone = true;
                _locChannel?.unsubscribe();
                _locationPollTimer?.cancel();
                // Remove rider pin and route so the map is clean after confirmation.
                _riderLocation  = null;
                _locationIsLive = false;
                _routePoints    = [];
                _etaSeconds     = null;
              }
            });
            if (s == 'awaiting_pickup_confirm') {
              Get.snackbar(
                widget.isRecipient
                    ? '📍 Rider at Sender\'s Location'
                    : '📍 Rider Has Arrived',
                widget.isRecipient
                    ? 'Rider is at the sender\'s location, awaiting handoff.'
                    : 'Your rider is at the pickup location — please confirm the handoff.',
                backgroundColor: const Color(0xFFD97706),
                colorText: Colors.white,
                snackPosition: SnackPosition.TOP,
                duration: const Duration(seconds: 5),
              );
            }
            // If rider was just assigned, re-init to get their GPS
            if (s == 'assigned' && _status == 'waiting') {
              await _init();
            }
            final r = _riderLocation;
            if (r != null) _checkArrival(r.latitude, r.longitude);
            await _fetchRoute();
          })
        .subscribe();
  }

  Future<void> _confirmReceipt() async {
    setState(() => _confirmLoading = true);
    try {
      await _db.from('deliveries').update({
        'status':       'confirmed',
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.deliveryId);
      if (mounted) {
        setState(() { _deliveryDone = true; _confirmLoading = false; });
        Get.snackbar('Receipt Confirmed',
            'Thank you! Your delivery is now complete.',
            backgroundColor: EzizaColors.kSuccess,
            colorText: EzizaColors.kWhite,
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 4));
      }
    } catch (_) {
      Get.snackbar('Error', 'Could not confirm. Try again.',
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
      if (mounted) setState(() => _confirmLoading = false);
    }
  }

  Future<void> _confirmHandoff() async {
    setState(() => _confirmHandoffLoading = true);
    try {
      await _db.from('deliveries').update({
        'status':    'picked_up',
        'picked_up_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.deliveryId);
      if (mounted) setState(() => _confirmHandoffLoading = false);
    } catch (_) {
      Get.snackbar('Error', 'Could not confirm handoff. Try again.',
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
      if (mounted) setState(() => _confirmHandoffLoading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setStatus(String s) { if (mounted) setState(() => _status = s); }

  Future<LatLng?> _geocode(String addr) async {
    if (addr.trim().isEmpty) return null;
    try {
      final enc = Uri.encodeComponent('$addr, Nigeria');
      final url = 'https://nominatim.openstreetmap.org/search'
          '?q=$enc&format=json&limit=1&countrycodes=ng';
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'EzizaRider/1.0'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List?;
        if (list != null && list.isNotEmpty) {
          final lat = double.tryParse(list[0]['lat'].toString());
          final lon = double.tryParse(list[0]['lon'].toString());
          if (lat != null && lon != null) return LatLng(lat, lon);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchRoute() async {
    final from = _riderLocation;
    if (from == null) return;
    final to = _phase == 'to_pickup' ? _pickupLatLng : _dropoffLatLng;
    if (to == null) return;
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson';
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'EzizaRider/1.0'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data   = jsonDecode(resp.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final coords = routes[0]['geometry']['coordinates'] as List;
          final pts = coords
              .map<LatLng>((c) =>
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          final dur = (routes[0]['duration'] as num?)?.toInt();
          if (mounted) setState(() { _routePoints = pts; _etaSeconds = dur; });
        }
      }
    } catch (_) {}
  }

  void _fitMap() {
    if (_initialFit) return;
    final pts = [
      ?_riderLocation,
      ?_pickupLatLng,
      ?_dropoffLatLng,
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) { _mapCtrl.move(pts.first, 14); _initialFit = true; return; }
    final lats = pts.map((p) => p.latitude);
    final lngs = pts.map((p) => p.longitude);
    _mapCtrl.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(lats.reduce(math.min) - 0.02, lngs.reduce(math.min) - 0.02),
        LatLng(lats.reduce(math.max) + 0.02, lngs.reduce(math.max) + 0.02),
      ),
      padding: const EdgeInsets.fromLTRB(40, 80, 40, 260),
    ));
    _initialFit = true;
  }

  void _checkArrival(double rLat, double rLng) {
    if (_phase != 'to_dropoff') return;
    final dest = _dropoffLatLng;
    if (dest == null) return;
    final distM = Geolocator.distanceBetween(rLat, rLng, dest.latitude, dest.longitude);
    if (distM <= 150 && mounted) {
      Get.snackbar(
        'Your rider has arrived!',
        'Your delivery is here — please come to the door.',
        backgroundColor: EzizaColors.kSuccess,
        colorText: EzizaColors.kWhite,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 5),
      );
    }
  }

  String _etaLabel() {
    if (_etaSeconds == null) return '…';
    if (_etaSeconds! < 60) return '< 1 min';
    if (_etaSeconds! < 3600) return '${(_etaSeconds! / 60).round()} min';
    final h = _etaSeconds! ~/ 3600;
    final m = (_etaSeconds! % 3600) ~/ 60;
    return m > 0 ? '${h}hr ${m}min' : '${h}hr';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final phaseColor = _phase == 'to_pickup' ? EzizaColors.kGold : EzizaColors.kPurple;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter:
                _riderLocation ?? _pickupLatLng ?? _dropoffLatLng ?? _ngDefault,
            initialZoom: _riderLocation != null ? 14.0 : 6.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.eziza.rider',
            ),

            // Route polyline
            if (_routePoints.isNotEmpty)
              PolylineLayer(polylines: [
                Polyline(
                  points:           _routePoints,
                  strokeWidth:      4.5,
                  color:            phaseColor.withValues(alpha: 0.85),
                  borderStrokeWidth: 1.5,
                  borderColor:      Colors.white.withValues(alpha: 0.5),
                ),
              ]),

            // Pickup pin — gold store with "Pickup" label
            if (_pickupLatLng != null)
              MarkerLayer(markers: [
                Marker(
                  point: _pickupLatLng!,
                  width: 72, height: 90,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EzizaColors.kGold,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4, offset: const Offset(0, 1))],
                      ),
                      child: const Text('Pickup',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3)),
                    ),
                    const SizedBox(height: 2),
                    Stack(alignment: Alignment.center, children: [
                      if (_phase == 'to_pickup')
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 800),
                          width: _pulse ? 52 : 42, height: _pulse ? 52 : 42,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: EzizaColors.kGold
                                  .withValues(alpha: _pulse ? 0.18 : 0.08)),
                        ),
                      Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                              color:  EzizaColors.kGold,
                              shape:  BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [BoxShadow(
                                  color: EzizaColors.kGold
                                      .withValues(alpha: _phase == 'to_pickup' ? 0.6 : 0.3),
                                  blurRadius: _phase == 'to_pickup' ? 12 : 6,
                                  spreadRadius: _phase == 'to_pickup' ? 2 : 0)]),
                          child: const Icon(Icons.store_rounded,
                              color: Colors.white, size: 18)),
                    ]),
                    Container(width: 2, height: 10, color: EzizaColors.kGold),
                  ]),
                ),
              ]),

            // Dropoff pin — purple home with "Dropoff" label
            if (_dropoffLatLng != null)
              MarkerLayer(markers: [
                Marker(
                  point: _dropoffLatLng!,
                  width: 72, height: 90,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EzizaColors.kPurple,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4, offset: const Offset(0, 1))],
                      ),
                      child: const Text('Dropoff',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3)),
                    ),
                    const SizedBox(height: 2),
                    Stack(alignment: Alignment.center, children: [
                      if (_phase == 'to_dropoff')
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 800),
                          width: _pulse ? 52 : 42, height: _pulse ? 52 : 42,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: EzizaColors.kPurple
                                  .withValues(alpha: _pulse ? 0.18 : 0.08)),
                        ),
                      Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                              color:  EzizaColors.kPurple,
                              shape:  BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [BoxShadow(
                                  color: EzizaColors.kPurple
                                      .withValues(alpha: _phase == 'to_dropoff' ? 0.6 : 0.3),
                                  blurRadius: _phase == 'to_dropoff' ? 12 : 6,
                                  spreadRadius: _phase == 'to_dropoff' ? 2 : 0)]),
                          child: const Icon(Icons.home_rounded,
                              color: Colors.white, size: 18)),
                    ]),
                    Container(width: 2, height: 10, color: EzizaColors.kPurple),
                  ]),
                ),
              ]),

            // Rider dot — gold pulsing
            if (_riderLocation != null)
              MarkerLayer(markers: [
                Marker(
                  point: _riderLocation!,
                  width: 60, height: 70,
                  child: Stack(alignment: Alignment.center, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      width: _pulse ? 52 : 42, height: _pulse ? 52 : 42,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: EzizaColors.kGold
                              .withValues(alpha: _pulse ? 0.15 : 0.3)),
                    ),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                              color:  EzizaColors.kGold,
                              shape:  BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [BoxShadow(
                                  color: EzizaColors.kGold.withValues(alpha: 0.5),
                                  blurRadius: 10, spreadRadius: 2)]),
                          child: const Icon(Icons.delivery_dining,
                              color: Colors.white, size: 20)),
                      Container(width: 2, height: 8, color: EzizaColors.kGold),
                    ]),
                  ]),
                ),
              ]),
          ],
        ),

        // ── Top bar ──────────────────────────────────────────────
        Positioned(top: 0, left: 0, right: 0,
          child: SafeArea(bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: Get.back,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:        Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow:    [BoxShadow(
                          color:     Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8)]),
                    child: const Icon(Icons.arrow_back_ios_new,
                        size: 16, color: EzizaColors.kText)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color:        Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow:    [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8)]),
                  child: Row(children: [
                    const Icon(Icons.local_shipping_outlined,
                        color: EzizaColors.kPurple, size: 18),
                    const SizedBox(width: 8),
                    const Text('Live Tracking',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 14, color: EzizaColors.kText)),
                    const Spacer(),
                    _statusDot(),
                  ]),
                )),
              ]),
            ),
          )),

        // ── Bottom card ───────────────────────────────────────────
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomCard()),
      ]),
    );
  }

  Widget _statusDot() {
    if (_status == 'live') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          width: 8, height: 8,
          decoration: BoxDecoration(
              color: _pulse ? Colors.green : Colors.green.shade300,
              shape: BoxShape.circle)),
        const SizedBox(width: 4),
        const Text('Live',
            style: TextStyle(fontSize: 11, color: Colors.green,
                fontWeight: FontWeight.w700)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8,
          decoration: const BoxDecoration(
              color: EzizaColors.kMuted, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      const Text('Waiting',
          style: TextStyle(fontSize: 11, color: EzizaColors.kMuted,
              fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _buildBottomCard() => Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20, offset: const Offset(0, -4))]),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _status == 'loading'
            ? const Center(child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: EzizaColors.kPurple)))
            : _status == 'no_delivery'
                ? _noDeliveryCard()
                : _status == 'waiting'
                    ? _waitingCard()
                    : _liveCard(),
      ));

  Widget _noDeliveryCard() => const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.info_outline, color: EzizaColors.kMuted, size: 20),
          SizedBox(width: 8),
          Text('Delivery Not Found',
              style: TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 15, color: EzizaColors.kText)),
        ]),
        SizedBox(height: 10),
        Text('This delivery could not be found or is no longer available.',
            style: TextStyle(fontSize: 13,
                color: EzizaColors.kMuted, height: 1.4)),
      ]);

  Widget _waitingCard() => const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          SizedBox(width: 10, height: 10,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: EzizaColors.kGold)),
          SizedBox(width: 10),
          Text('Waiting for Rider',
              style: TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 15, color: EzizaColors.kText)),
        ]),
        SizedBox(height: 10),
        Text(
            'Your request is open for bids. Once a rider is assigned, '
            'their live location will appear here.',
            style: TextStyle(fontSize: 13,
                color: EzizaColors.kMuted, height: 1.4)),
      ]);

  Widget _liveCard() {
    final name    = _riderInfo?['full_name']    as String? ?? 'Your Rider';
    final phone   = _riderInfo?['phone']        as String? ?? '';
    final vehicle = _riderInfo?['vehicle_type'] as String? ?? 'bike';

    const vIcon = {
      'bike': '🏍️', 'car': '🚗', 'van': '🚐',
      'bicycle': '🚲', 'foot': '🚶',
    };

    final phaseLabel  = _phase == 'to_pickup' ? 'Heading to pickup' : 'On the way to you';
    final etaTitle    = _phase == 'to_pickup' ? 'ETA to Pickup' : 'ETA to Delivery';
    final etaColor    = _phase == 'to_pickup' ? EzizaColors.kGold : EzizaColors.kPurple;

    return Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      // Rider info
      Row(children: [
        Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: EzizaColors.kGold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: EzizaColors.kGold.withValues(alpha: 0.3))),
            child: Center(child: Text(
                vIcon[vehicle] ?? '🏍️',
                style: const TextStyle(fontSize: 22)))),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(name, style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: EzizaColors.kText)),
          Text(phaseLabel,
              style: const TextStyle(fontSize: 12, color: EzizaColors.kMuted)),
        ])),
        if (phone.isNotEmpty)
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('tel:$phone')),
            child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: EzizaColors.kPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.phone_outlined,
                    color: EzizaColors.kPurple, size: 20)),
          ),
      ]),

      // ETA
      if (_riderLocation != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: etaColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: etaColor.withValues(alpha: 0.25))),
          child: Row(children: [
            Icon(_phase == 'to_pickup'
                ? Icons.store_rounded : Icons.home_rounded,
                size: 16, color: etaColor),
            const SizedBox(width: 8),
            Expanded(child: Text(etaTitle,
                style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w600, color: etaColor))),
            Text(_etaLabel(),
                style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w800, color: etaColor)),
          ]),
        ),
      ],

      // Stale / no location
      if (_riderLocation == null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: EzizaColors.kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: EzizaColors.kGold.withValues(alpha: 0.2))),
          child: const Text('📡 Waiting for rider\'s location…',
              style: TextStyle(fontSize: 12, color: Color(0xFFD97706))),
        ),
      ] else if (!_locationIsLive) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBAE6FD))),
          child: const Row(children: [
            Icon(Icons.location_searching, size: 13, color: Color(0xFF0284C7)),
            SizedBox(width: 6),
            Expanded(child: Text(
              'Showing last known location · Updates live when rider moves',
              style: TextStyle(fontSize: 11, color: Color(0xFF0369A1)),
            )),
          ]),
        ),
      ],

      // Rider arrived — confirm handoff (sender only, not recipient)
      if (!widget.isRecipient && _delivery?['status'] == 'awaiting_pickup_confirm') ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.4)),
          ),
          child: const Row(children: [
            Icon(Icons.location_on_rounded, color: Color(0xFFD97706), size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Your rider is at the pickup location',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: Color(0xFF92400E)),
            )),
          ]),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _confirmHandoffLoading ? null : _confirmHandoff,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _confirmHandoffLoading
                  ? const Color(0xFFD97706).withValues(alpha: 0.5)
                  : const Color(0xFFD97706),
              borderRadius: BorderRadius.circular(14),
              boxShadow: _confirmHandoffLoading
                  ? const []
                  : [BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.3),
                      blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: _confirmHandoffLoading
                ? const Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)))
                : const Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.handshake_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Confirm Handoff',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
          ),
        ),
      ],

      // Confirm receipt
      if (_delivery?['status'] == 'delivered' && !_deliveryDone) ...[
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _confirmLoading ? null : _confirmReceipt,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _confirmLoading
                  ? EzizaColors.kSuccess.withValues(alpha: 0.5)
                  : EzizaColors.kSuccess,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _confirmLoading
                  ? const []
                  : [BoxShadow(
                      color: EzizaColors.kSuccess.withValues(alpha: 0.3),
                      blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: _confirmLoading
                ? const Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)))
                : const Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Confirm Receipt',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
          ),
        ),
      ],

      // Done state
      if (_deliveryDone) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color:        const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF86EFAC))),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF16A34A), size: 18),
            const SizedBox(width: 8),
            Text(
                widget.isRecipient
                    ? 'You confirmed receipt — delivery complete!'
                    : 'Receiver has confirmed receipt — delivery complete!',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF166534))),
          ]),
        ),
      ],
    ]);
  }
}
