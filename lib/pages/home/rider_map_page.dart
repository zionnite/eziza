import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/colors.dart';

const _ngDefault = LatLng(9.0820, 8.6753);

/// Full-screen navigation map for the rider during an active delivery.
/// Shows their live GPS, pickup + dropoff pins, OSRM route polyline, and ETA.
class RiderMapPage extends StatefulWidget {
  const RiderMapPage({
    super.key,
    required this.delivery,
    required this.riderId,
  });

  /// The full deliveries row (must include id, status, pickup/delivery coords+contacts).
  final Map<String, dynamic> delivery;

  /// riders.id (row UUID) for the current rider — used for status updates.
  final String riderId;

  @override
  State<RiderMapPage> createState() => _RiderMapPageState();
}

class _RiderMapPageState extends State<RiderMapPage> {
  final _mapCtrl = MapController();
  final _db      = Supabase.instance.client;

  LatLng? _myLocation;
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  List<LatLng> _routePoints = [];
  int? _etaSeconds;

  // to_pickup → to_dropoff
  String _phase = 'to_pickup';

  bool _initialFit       = false;
  bool _locating         = true;
  bool _actionLoading    = false;
  bool _waitingHandoff   = false; // awaiting_pickup_confirm — waiting for merchant/customer handoff
  bool _waitingCustomer  = false; // delivered — waiting for customer receipt confirmation
  bool _pulse            = false;

  String _pickupContact  = '';
  String _pickupPhone    = '';
  String _dropoffContact = '';
  String _dropoffPhone   = '';

  StreamSubscription<Position>? _gpsSub;
  RealtimeChannel? _statusChannel;
  Timer? _pulseTimer;
  Timer? _pollTimer;

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
    _gpsSub?.cancel();
    if (_statusChannel != null) _db.removeChannel(_statusChannel!);
    _pulseTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final delivId = widget.delivery['id'] as String;
    // Re-fetch from DB so status is current (widget.delivery from dashboard cache may be stale)
    final fresh = await _db.from('deliveries').select().eq('id', delivId).maybeSingle();
    final d      = fresh ?? widget.delivery;
    final status = d['status'] as String? ?? 'assigned';

    _phase = (status == 'picked_up' || status == 'delivered')
        ? 'to_dropoff'
        : 'to_pickup';
    if (status == 'awaiting_pickup_confirm') _waitingHandoff  = true;
    if (status == 'delivered') {
      _waitingCustomer = true;
      _startConfirmPoll(); // start poll immediately if page opened mid-wait
    }

    // Contact info from delivery columns
    _pickupContact  = d['pickup_contact_name']   as String? ?? '';
    _pickupPhone    = d['pickup_contact_phone']  as String? ?? '';
    _dropoffContact = d['delivery_contact_name']  as String? ?? '';
    _dropoffPhone   = d['delivery_contact_phone'] as String? ?? '';

    // Resolve pickup / dropoff GPS
    final pLat = (d['pickup_lat']   as num?)?.toDouble();
    final pLng = (d['pickup_lng']   as num?)?.toDouble();
    final dLat = (d['dropoff_lat'] as num?)?.toDouble();
    final dLng = (d['dropoff_lng'] as num?)?.toDouble();

    final resolvedPickup = (pLat != null && pLng != null)
        ? LatLng(pLat, pLng)
        : await _geocode(d['pickup_address']   as String? ?? '');
    final resolvedDropoff = (dLat != null && dLng != null)
        ? LatLng(dLat, dLng)
        : await _geocode(d['delivery_address'] as String? ?? '');

    if (mounted) {
      setState(() {
        _pickupLatLng  = resolvedPickup;
        _dropoffLatLng = resolvedDropoff;
      });
    }

    // Realtime: watch this delivery's status changes
    _statusChannel = _db
        .channel('rider_map_$delivId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'id',
            value:  delivId,
          ),
          callback: (p) {
            if (p.newRecord['id'] != delivId || !mounted) return;
            final s = p.newRecord['status'] as String? ?? '';
            switch (s) {
              case 'picked_up':
                // Customer confirmed handoff — advance the map to dropoff phase
                setState(() {
                  _waitingHandoff = false;
                  _phase          = 'to_dropoff';
                  _routePoints    = [];
                  _etaSeconds     = null;
                  _initialFit     = false;
                });
                _fetchRoute().then((_) => _fitMap());
                Get.snackbar(
                  'Handoff Confirmed',
                  'Customer confirmed pickup. Head to the delivery address!',
                  backgroundColor: EzizaColors.kPurple,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.TOP,
                  duration: const Duration(seconds: 3),
                );
              case 'delivered':
                setState(() => _waitingCustomer = true);
              case 'confirmed':
                _pollTimer?.cancel();
                _gpsSub?.cancel();
                _gpsSub = null;
                FlutterForegroundTask.updateService(
                  notificationTitle: 'Delivery Complete ✅',
                  notificationText: 'Great work! Earnings credited.',
                );
                Get.back(result: 'confirmed');
                Get.snackbar(
                  'Delivery Complete! 🎉',
                  'Customer confirmed receipt. Your earnings have been credited!',
                  backgroundColor: EzizaColors.kSuccess,
                  colorText: EzizaColors.kWhite,
                  snackPosition: SnackPosition.BOTTOM,
                  duration: const Duration(seconds: 5),
                );
            }
          })
        .subscribe();

    // GPS permission + stream
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _locating = false);
      return;
    }

    final uid = _db.auth.currentUser?.id;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
          _locating   = false;
        });
        await _fetchRoute();
        _fitMap();
      }
      // Publish initial position immediately so customer tracking map shows rider
      if (uid != null) {
        try {
          await _db.from('rider_locations').upsert({
            'rider_id':   uid,
            'latitude':   pos.latitude,
            'longitude':  pos.longitude,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((pos) async {
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (uid != null) {
        try {
          await _db.from('rider_locations').upsert({
            'rider_id':   uid,
            'latitude':   pos.latitude,
            'longitude':  pos.longitude,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}
      }
      await _fetchRoute();
      if (!_initialFit) _fitMap();
    });
  }

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
    final from = _myLocation;
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
      ?_myLocation,
      if (_phase == 'to_pickup') ?_pickupLatLng,
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

  Future<void> _confirmPickup() async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await _db
          .from('deliveries')
          .update({'status': 'awaiting_pickup_confirm'})
          .eq('id', widget.delivery['id']);
      if (mounted) {
        setState(() => _waitingHandoff = true);
        FlutterForegroundTask.updateService(
          notificationTitle: 'Awaiting Handoff Confirmation',
          notificationText: 'Waiting for merchant to confirm handoff…',
        );
        Get.snackbar(
          'Merchant Notified',
          'Waiting for the merchant to confirm the handoff.',
          backgroundColor: EzizaColors.kGold,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (_) {
      Get.snackbar('Error', 'Could not notify merchant. Try again.',
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  Future<void> _confirmDelivery() async {
    if (_actionLoading) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Delivery?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16,
                color: EzizaColors.kText)),
        content: const Text(
            'Only confirm once you have handed the package to the recipient '
            'at the correct address.',
            style: TextStyle(fontSize: 13, color: EzizaColors.kMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not Yet',
                  style: TextStyle(color: EzizaColors.kMuted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: EzizaColors.kSuccess,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Yes, Delivered',
                  style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await _db
          .from('deliveries')
          .update({
            'status':       'delivered',
            'delivered_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.delivery['id']);
      if (mounted) {
        setState(() => _waitingCustomer = true);
        _startConfirmPoll();
        FlutterForegroundTask.updateService(
          notificationTitle: 'Package Delivered ✅',
          notificationText: 'Waiting for customer to confirm receipt',
        );
        Get.snackbar(
          'Package Delivered!',
          'Waiting for customer to confirm receipt…',
          backgroundColor: EzizaColors.kSuccess,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (_) {
      Get.snackbar('Error', 'Could not confirm delivery. Try again.',
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  void _startConfirmPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || !_waitingCustomer) { _pollTimer?.cancel(); return; }
      try {
        final row = await _db
            .from('deliveries')
            .select('status')
            .eq('id', widget.delivery['id'])
            .maybeSingle();
        if ((row?['status'] as String?) == 'confirmed' && mounted) {
          _pollTimer?.cancel();
          _gpsSub?.cancel();
          _gpsSub = null;
          Get.back(result: 'confirmed');
          Get.snackbar(
            'Delivery Complete! 🎉',
            'Customer confirmed receipt. Your earnings have been credited!',
            backgroundColor: EzizaColors.kSuccess,
            colorText: EzizaColors.kWhite,
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 5),
          );
        }
      } catch (_) {}
    });
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
    final d        = widget.delivery;
    final pickup   = d['pickup_address']   as String? ?? '';
    final delivery = d['delivery_address'] as String? ?? '';

    // Lock back-gesture only during active dropoff navigation.
    // When _waitingCustomer is true the package is already handed over —
    // both the back button and the realtime 'confirmed' Get.back() must work.
    final lockedIn = _phase == 'to_dropoff' && !_waitingCustomer;

    return PopScope(
      canPop: !lockedIn,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter:
                _myLocation ?? _pickupLatLng ?? _dropoffLatLng ?? _ngDefault,
            initialZoom: _myLocation != null ? 14.0 : 6.0,
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
                  strokeWidth:      4,
                  color:            EzizaColors.kPurple.withValues(alpha: 0.75),
                  borderStrokeWidth: 1.5,
                  borderColor:      Colors.white.withValues(alpha: 0.5),
                ),
              ]),

            // Pickup marker — only shown while heading to pickup (already visited after that)
            if (_pickupLatLng != null && _phase == 'to_pickup')
              MarkerLayer(markers: [
                Marker(
                  point: _pickupLatLng!,
                  width: 44, height: 54,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color:  EzizaColors.kGold,
                        shape:  BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [BoxShadow(
                            color:     EzizaColors.kGold.withValues(alpha: 0.5),
                            blurRadius: 8, spreadRadius: 2)]),
                      child: const Icon(Icons.store_rounded,
                          color: Colors.white, size: 18)),
                    Container(width: 2, height: 10, color: EzizaColors.kGold),
                  ]),
                ),
              ]),

            // Dropoff marker — purple home
            if (_dropoffLatLng != null)
              MarkerLayer(markers: [
                Marker(
                  point: _dropoffLatLng!,
                  width: 44, height: 54,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color:  EzizaColors.kPurple,
                        shape:  BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [BoxShadow(
                            color:     EzizaColors.kPurple.withValues(alpha: 0.5),
                            blurRadius: 8, spreadRadius: 2)]),
                      child: const Icon(Icons.home_rounded,
                          color: Colors.white, size: 18)),
                    Container(width: 2, height: 10, color: EzizaColors.kPurple),
                  ]),
                ),
              ]),

            // My position — blue pulsing dot
            if (_myLocation != null)
              MarkerLayer(markers: [
                Marker(
                  point: _myLocation!,
                  width: 60, height: 60,
                  child: Stack(alignment: Alignment.center, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      width:  _pulse ? 48 : 36,
                      height: _pulse ? 48 : 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2563EB)
                            .withValues(alpha: _pulse ? 0.15 : 0.3)),
                    ),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color:  const Color(0xFF2563EB),
                        shape:  BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [BoxShadow(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.5),
                            blurRadius: 8, spreadRadius: 2)]),
                      child: const Icon(Icons.delivery_dining,
                          color: Colors.white, size: 14)),
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
                    const Icon(Icons.map_rounded,
                        color: EzizaColors.kPurple, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                        '${_shortAddr(pickup)} → ${_shortAddr(delivery)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: EzizaColors.kText),
                        overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('You',
                        style: TextStyle(fontSize: 11,
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w700)),
                  ]),
                )),
              ]),
            ),
          )),

        // ── Bottom card ───────────────────────────────────────────
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow:    [BoxShadow(
                  color:     Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset:    const Offset(0, -4))]),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _locating
                  ? const Row(children: [
                      SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: EzizaColors.kPurpleD)),
                      SizedBox(width: 12),
                      Text('Getting your location…',
                          style: TextStyle(
                              fontSize: 13, color: EzizaColors.kMuted)),
                    ])
                  : _bottomContent(),
            ),
          )),
      ]),
      ), // Scaffold
    ); // PopScope
  }

  Widget _bottomContent() {
    final isPickup = _phase == 'to_pickup';
    final contact  = isPickup ? _pickupContact  : _dropoffContact;
    final phone    = isPickup ? _pickupPhone    : _dropoffPhone;
    final addr     = isPickup
        ? (widget.delivery['pickup_address']   as String? ?? '')
        : (widget.delivery['delivery_address'] as String? ?? '');
    final phaseColor = isPickup ? EzizaColors.kGold : EzizaColors.kPurple;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Phase indicator
      Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: phaseColor.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(
              isPickup ? Icons.store_rounded : Icons.home_rounded,
              color: phaseColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(isPickup ? 'Head to pickup' : 'Head to delivery address',
              style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 14, color: EzizaColors.kText)),
          Text(addr,
              style: const TextStyle(fontSize: 12, color: EzizaColors.kMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),

      const SizedBox(height: 12),

      // ETA row
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: phaseColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: phaseColor.withValues(alpha: 0.25))),
        child: Row(children: [
          Icon(Icons.timer_outlined, size: 16, color: phaseColor),
          const SizedBox(width: 8),
          Expanded(child: Text(
              isPickup ? 'ETA to Pickup' : 'ETA to Delivery',
              style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: phaseColor))),
          Text(_etaLabel(),
              style: TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w800, color: phaseColor)),
        ]),
      ),

      // GPS warning
      if (_myLocation == null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: EzizaColors.kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
          child: const Text('📡 Could not get GPS — check location permissions.',
              style: TextStyle(fontSize: 12, color: Color(0xFFD97706))),
        ),
      ],

      // Call button
      if (phone.isNotEmpty) ...[
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse('tel:$phone')),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
                color:  const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.4))),
            child: Row(children: [
              const Icon(Icons.phone_rounded,
                  size: 18, color: Color(0xFF4F46E5)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(isPickup ? 'Call Pickup Contact' : 'Call Recipient',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4F46E5))),
                if (contact.isNotEmpty)
                  Text(contact,
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: EzizaColors.kText)),
              ])),
              Text(phone,
                  style: const TextStyle(fontSize: 12,
                      color: Color(0xFF4F46E5),
                      fontFamily: 'monospace')),
            ]),
          ),
        ),
      ],

      const SizedBox(height: 14),

      // Action button
      if (_waitingCustomer)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color:        const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: EzizaColors.kSuccess.withValues(alpha: 0.4))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: EzizaColors.kSuccess)),
              SizedBox(width: 12),
              Expanded(child: Text(
                'Package delivered — waiting for customer to confirm receipt…',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: Color(0xFF166534)),
              )),
            ]),
        )
      else if (_waitingHandoff)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color:        const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: EzizaColors.kGold.withValues(alpha: 0.5))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: EzizaColors.kGold)),
              SizedBox(width: 12),
              Expanded(child: Text(
                'Merchant notified — waiting for them to confirm the handoff…',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: Color(0xFF92400E)),
              )),
            ]),
        )
      else if (_phase == 'to_pickup')
        _actionBtn(
          label:   'Notify Merchant for Pickup',
          icon:    Icons.store_rounded,
          bgColor: EzizaColors.kGold,
          onTap:   _confirmPickup,
        )
      else
        _actionBtn(
          label:   'Confirm Delivery',
          icon:    Icons.check_circle_rounded,
          bgColor: EzizaColors.kSuccess,
          onTap:   _confirmDelivery,
        ),
    ]);
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color bgColor,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: _actionLoading ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _actionLoading
                ? bgColor.withValues(alpha: 0.5)
                : bgColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _actionLoading
                ? const []
                : [BoxShadow(
                    color:     bgColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset:    const Offset(0, 4))],
          ),
          child: _actionLoading
              ? const Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
        ),
      );

  String _shortAddr(String addr) {
    final comma = addr.indexOf(',');
    final raw   = comma == -1 ? addr : addr.substring(0, comma);
    return raw.length > 22 ? '${raw.substring(0, 19)}…' : raw;
  }
}
