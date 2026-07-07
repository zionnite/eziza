import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';

const _ngDefault = LatLng(9.0820, 8.6753);

/// Company fleet overview map — all company riders shown simultaneously
/// with live GPS dots, route polylines, and destination markers.
class CompanyMapPage extends StatefulWidget {
  const CompanyMapPage({super.key, required this.riders});

  /// riders rows: must include id (riders.id), auth_user_id, full_name, is_available.
  final List<Map<String, dynamic>> riders;

  @override
  State<CompanyMapPage> createState() => _CompanyMapPageState();
}

class _CompanyMapPageState extends State<CompanyMapPage> {
  final _db      = Supabase.instance.client;
  final _mapCtrl = MapController();

  final Map<String, _RiderPin> _pins = {};

  bool   _loading = true;
  Timer? _refreshTimer;
  Timer? _pulseTimer;
  RealtimeChannel? _locChannel;
  RealtimeChannel? _delChannel;
  bool _pulse = false;

  static const _palette = [
    EzizaColors.kGold,
    EzizaColors.kPurple,
    Color(0xFF0284C7),
    Color(0xFF16A34A),
    Color(0xFFDC2626),
    Color(0xFF9333EA),
    Color(0xFFD97706),
    Color(0xFF0D9488),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _load());
    _pulseTimer   = Timer.periodic(
        const Duration(milliseconds: 800),
        (_) { if (mounted) setState(() => _pulse = !_pulse); });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseTimer?.cancel();
    if (_locChannel != null) _db.removeChannel(_locChannel!);
    if (_delChannel != null) _db.removeChannel(_delChannel!);
    super.dispose();
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    if (widget.riders.isEmpty) return;

    // auth UIDs for rider_locations
    final authUids = widget.riders
        .map((r) => r['auth_user_id'] as String?)
        .whereType<String>()
        .toList();
    if (authUids.isEmpty) return;

    _locChannel = _db
        .channel('company_map_locs')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rider_locations',
          callback: (p) => _applyLocRow(p.newRecord))
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rider_locations',
          callback: (p) => _applyLocRow(p.newRecord))
        .subscribe();

    _delChannel = _db
        .channel('company_map_deliveries')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          callback: (p) => _applyDeliveryChange(p.newRecord))
        .subscribe();
  }

  void _applyLocRow(Map<String, dynamic> row) {
    // row['rider_id'] is auth.uid()
    final authUid = row['rider_id'] as String?;
    if (authUid == null) return;

    // Find the rider by auth_user_id
    final riderRow = widget.riders.firstWhereOrNull(
        (r) => r['auth_user_id'] == authUid);
    if (riderRow == null || !mounted) return;

    final riderId = riderRow['id'] as String;
    final lat = (row['latitude']  as num?)?.toDouble();
    final lng = (row['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final idx      = _riderIndex(riderId);
    final existing = _pins[riderId];

    final pin = _RiderPin(
      location:           LatLng(lat, lng),
      name:               riderRow['full_name'] as String? ?? 'Rider',
      online:             riderRow['is_available'] as bool? ?? true,
      color:              _palette[idx % _palette.length],
      phase:              existing?.phase,
      destination:        existing?.destination,
      destinationLabel:   existing?.destinationLabel,
      destinationAddress: existing?.destinationAddress,
      routePoints:        existing?.routePoints ?? [],
    );

    if (mounted) {
      setState(() => _pins[riderId] = pin);
      _refreshOneRoute(riderId, LatLng(lat, lng));
    }
  }

  void _applyDeliveryChange(Map<String, dynamic> row) {
    // deliveries.rider_id is riders.id (UUID), not auth UID
    final riderRowId = row['rider_id'] as String?;
    if (riderRowId == null || !_pins.containsKey(riderRowId) || !mounted) {
      return;
    }
    final status   = row['status'] as String? ?? '';
    final existing = _pins[riderRowId]!;

    if (status == 'confirmed' || status == 'cancelled') {
      setState(() => _pins[riderRowId] = _RiderPin(
        location: existing.location, name: existing.name,
        online: existing.online, color: existing.color,
      ));
      return;
    }
    if (status == 'picked_up') {
      final dLat  = (row['delivery_lat'] as num?)?.toDouble();
      final dLng  = (row['delivery_lng'] as num?)?.toDouble();
      final dAddr = row['delivery_address'] as String?;
      if (dLat == null || dLng == null) return;
      final dest = LatLng(dLat, dLng);
      setState(() => _pins[riderRowId] = _RiderPin(
        location:           existing.location,
        name:               existing.name,
        online:             existing.online,
        color:              existing.color,
        phase:              'to_dropoff',
        destination:        dest,
        destinationLabel:   'Dropoff',
        destinationAddress: dAddr,
        routePoints:        [existing.location, dest],
      ));
      _refreshOneRoute(riderRowId, existing.location);
    }
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (widget.riders.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // riders.id list (for deliveries lookup)
    final riderIds = widget.riders
        .map((r) => r['id'] as String?)
        .whereType<String>()
        .toList();
    // auth_user_id list (for rider_locations lookup)
    final authUids = widget.riders
        .map((r) => r['auth_user_id'] as String?)
        .whereType<String>()
        .toList();

    if (riderIds.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // GPS positions
      final locRows = await _db
          .from('rider_locations')
          .select('rider_id, latitude, longitude, updated_at')
          .inFilter('rider_id', authUids);

      // Active deliveries for these riders
      final assignRows = await _db
          .from('deliveries')
          .select('rider_id, status, '
              'pickup_lat, pickup_lng, pickup_address, '
              'delivery_lat, delivery_lng, delivery_address')
          .inFilter('rider_id', riderIds)
          .inFilter('status', ['assigned', 'picked_up']);

      final assignByRiderId = <String, Map<String, dynamic>>{};
      for (final a in assignRows) {
        final rid = a['rider_id'] as String?;
        if (rid != null) assignByRiderId[rid] = a;
      }

      // Build authUid → riderId map for joining
      final authUidToId = <String, String>{};
      for (final r in widget.riders) {
        final uid = r['auth_user_id'] as String?;
        final id  = r['id']          as String?;
        if (uid != null && id != null) authUidToId[uid] = id;
      }

      final now             = DateTime.now().toUtc();
      const staleThreshold  = Duration(minutes: 5);
      final updated         = <String, _RiderPin>{};

      for (final row in locRows) {
        final authUid = row['rider_id'] as String?;
        if (authUid == null) continue;
        final riderId = authUidToId[authUid];
        if (riderId == null) continue;

        final lat = (row['latitude']  as num?)?.toDouble();
        final lng = (row['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        DateTime? updAt;
        try { updAt = DateTime.parse(row['updated_at'] as String).toUtc(); } catch (_) {}
        final stale = updAt != null && now.difference(updAt) > staleThreshold;

        final riderRow = widget.riders.firstWhereOrNull((r) => r['id'] == riderId);
        final idx      = _riderIndex(riderId);
        final assign   = assignByRiderId[riderId];

        String? phase, destLabel, destAddr;
        LatLng? destination;

        if (assign != null) {
          final s = assign['status'] as String? ?? 'assigned';
          phase   = s == 'picked_up' ? 'to_dropoff' : 'to_pickup';
          if (phase == 'to_pickup') {
            final pLat = (assign['pickup_lat']  as num?)?.toDouble();
            final pLng = (assign['pickup_lng']  as num?)?.toDouble();
            if (pLat != null && pLng != null) destination = LatLng(pLat, pLng);
            destLabel = 'Pickup';
            destAddr  = assign['pickup_address'] as String?;
          } else {
            final dLat = (assign['delivery_lat'] as num?)?.toDouble();
            final dLng = (assign['delivery_lng'] as num?)?.toDouble();
            if (dLat != null && dLng != null) destination = LatLng(dLat, dLng);
            destLabel = 'Dropoff';
            destAddr  = assign['delivery_address'] as String?;
          }
        }

        updated[riderId] = _RiderPin(
          location:           LatLng(lat, lng),
          name:               riderRow?['full_name'] as String? ?? 'Rider',
          online:             riderRow?['is_available'] as bool? ?? false,
          color:              _palette[idx % _palette.length],
          stale:              stale,
          staleFor:           updAt != null ? now.difference(updAt) : null,
          phase:              phase,
          destination:        destination,
          destinationLabel:   destLabel,
          destinationAddress: destAddr,
        );
      }

      // Fetch routes in parallel
      final futures = <MapEntry<String, Future<List<LatLng>>>>[];
      for (final e in updated.entries) {
        final dest = e.value.destination;
        if (dest != null) {
          futures.add(MapEntry(e.key,
              _fetchRoute(e.value.location, dest)));
        }
      }
      final routes = Map.fromEntries(
          await Future.wait(futures.map((e) async =>
              MapEntry(e.key, await e.value))));

      for (final rid in routes.keys) {
        final p = updated[rid];
        if (p != null) {
          updated[rid] = _RiderPin(
            location:           p.location,
            name:               p.name,
            online:             p.online,
            color:              p.color,
            stale:              p.stale,
            staleFor:           p.staleFor,
            phase:              p.phase,
            destination:        p.destination,
            destinationLabel:   p.destinationLabel,
            destinationAddress: p.destinationAddress,
            routePoints:        routes[rid] ?? [],
          );
        }
      }

      if (mounted) {
        setState(() {
          _pins
            ..clear()
            ..addAll(updated);
          _loading = false;
        });
        if (_pins.isNotEmpty) _fitAll();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshOneRoute(String riderId, LatLng from) async {
    final dest = _pins[riderId]?.destination;
    if (dest == null) return;
    final pts = await _fetchRoute(from, dest);
    if (!mounted || !_pins.containsKey(riderId)) return;
    final p = _pins[riderId]!;
    setState(() => _pins[riderId] = _RiderPin(
      location:           from,
      name:               p.name,
      online:             p.online,
      color:              p.color,
      stale:              p.stale,
      staleFor:           p.staleFor,
      phase:              p.phase,
      destination:        p.destination,
      destinationLabel:   p.destinationLabel,
      destinationAddress: p.destinationAddress,
      routePoints:        pts,
    ));
  }

  Future<List<LatLng>> _fetchRoute(LatLng from, LatLng to) async {
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
          return coords
              .map<LatLng>((c) =>
                  LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
        }
      }
    } catch (_) {}
    return [from, to];
  }

  void _fitAll() {
    if (_pins.isEmpty) return;
    final pts = [
      ..._pins.values.map((p) => p.location),
      ..._pins.values
          .where((p) => p.destination != null)
          .map((p) => p.destination!),
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) { _mapCtrl.move(pts.first, 14); return; }
    final lats = pts.map((p) => p.latitude);
    final lngs = pts.map((p) => p.longitude);
    _mapCtrl.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(lats.reduce(math.min) - 0.02, lngs.reduce(math.min) - 0.02),
        LatLng(lats.reduce(math.max) + 0.02, lngs.reduce(math.max) + 0.02),
      ),
      padding: const EdgeInsets.fromLTRB(40, 80, 40, 200),
    ));
  }

  int _riderIndex(String riderId) {
    final ids = widget.riders.map((r) => r['id'] as String).toList();
    final i   = ids.indexOf(riderId);
    return i == -1 ? 0 : i;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final onlineCount = _pins.values.where((p) => p.online).length;

    final polylines   = <Polyline>[];
    final destMarkers = <Marker>[];

    for (final e in _pins.entries) {
      final pin = e.value;
      if (pin.routePoints.length >= 2) {
        polylines.add(Polyline(
          points:            pin.routePoints,
          strokeWidth:       3.5,
          color:             pin.color.withValues(alpha: 0.8),
          borderStrokeWidth: 1.5,
          borderColor:       Colors.white.withValues(alpha: 0.4),
        ));
      }
      if (pin.destination != null) {
        final isPickup = pin.phase == 'to_pickup';
        destMarkers.add(Marker(
          point: pin.destination!,
          width: 48, height: 56,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12), blurRadius: 3)]),
              child: Text(
                pin.destinationLabel ?? (isPickup ? 'Pickup' : 'Drop'),
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                    color: pin.color)),
            ),
            const SizedBox(height: 2),
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color:  pin.color,
                shape:  BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(
                    color: pin.color.withValues(alpha: 0.4),
                    blurRadius: 6, spreadRadius: 1)]),
              child: Icon(
                  isPickup ? Icons.store_rounded : Icons.home_rounded,
                  color: Colors.white, size: 13)),
            Container(width: 2, height: 6, color: pin.color),
          ]),
        ));
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: const MapOptions(
            initialCenter: _ngDefault,
            initialZoom:   6,
          ),
          children: [
            TileLayer(
              urlTemplate:         'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.eziza.rider',
            ),
            if (polylines.isNotEmpty)
              PolylineLayer(polylines: polylines),
            if (destMarkers.isNotEmpty)
              MarkerLayer(markers: destMarkers),
            if (_pins.isNotEmpty)
              MarkerLayer(
                markers: _pins.entries.map((e) {
                  final pin = e.value;
                  return Marker(
                    point: pin.location,
                    width: 80, height: 70,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4)]),
                        child: Text(
                          pin.name.split(' ').first,
                          style: TextStyle(fontSize: 9,
                              fontWeight: FontWeight.w700, color: pin.color),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Stack(alignment: Alignment.center, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 800),
                          width:  _pulse ? 38 : 30,
                          height: _pulse ? 38 : 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: pin.color
                                .withValues(alpha: _pulse ? 0.15 : 0.25)),
                        ),
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color:  pin.color,
                            shape:  BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(
                                color: pin.color.withValues(alpha: 0.5),
                                blurRadius: 6, spreadRadius: 1)]),
                          child: const Icon(Icons.delivery_dining,
                              color: Colors.white, size: 13)),
                      ]),
                    ]),
                  );
                }).toList(),
              ),
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
                          color: Colors.black.withValues(alpha: 0.1),
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
                    const Icon(Icons.group_rounded,
                        color: EzizaColors.kPurple, size: 18),
                    const SizedBox(width: 8),
                    const Text('Riders Overview',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            fontSize: 14, color: EzizaColors.kText)),
                    const Spacer(),
                    if (_loading)
                      const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: EzizaColors.kPurple))
                    else ...[
                      Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                              color: onlineCount > 0
                                  ? Colors.green : EzizaColors.kMuted,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text('$onlineCount online',
                          style: const TextStyle(
                              fontSize: 11, color: EzizaColors.kMuted,
                              fontWeight: FontWeight.w600)),
                    ],
                  ]),
                )),
              ]),
            ),
          )),

        // ── Bottom panel ──────────────────────────────────────────
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow:    [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20, offset: const Offset(0, -4))]),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: EzizaColors.kPurple)))
                  : _bottomPanel(),
            ),
          )),
      ]),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _bottomPanel() {
    if (widget.riders.isEmpty) {
      return const Center(
        child: Text('No riders in your company yet.',
            style: TextStyle(fontSize: 13, color: EzizaColors.kMuted),
            textAlign: TextAlign.center),
      );
    }
    if (_pins.isEmpty) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
              color: Color(0xFFFFF8E1), shape: BoxShape.circle),
          child: const Icon(Icons.location_off_rounded,
              color: EzizaColors.kGold, size: 20)),
        const SizedBox(height: 8),
        const Text('No riders sharing their location right now.',
            style: TextStyle(fontSize: 13, color: EzizaColors.kMuted),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        const Text('Riders share location when they go online.',
            style: TextStyle(fontSize: 11, color: EzizaColors.kMuted),
            textAlign: TextAlign.center),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text('${_pins.length} rider${_pins.length == 1 ? '' : 's'} sharing location',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: EzizaColors.kText)),
      const SizedBox(height: 10),
      ..._pins.entries.map((e) {
        final pin = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                      color: pin.color, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pin.name,
                    style: const TextStyle(fontSize: 13,
                        color: EzizaColors.kText)),
                if (pin.phase != null && pin.destinationAddress != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(
                        pin.phase == 'to_pickup'
                            ? Icons.store_rounded : Icons.home_rounded,
                        size: 11, color: pin.color),
                    const SizedBox(width: 4),
                    Expanded(child: Text(
                      '${pin.phase == 'to_pickup' ? 'Heading to pickup' : 'Heading to dropoff'}: ${pin.destinationAddress}',
                      style: TextStyle(fontSize: 10, color: pin.color,
                          fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                ] else if (pin.phase == null) ...[
                  const SizedBox(height: 2),
                  const Text('No active delivery',
                      style: TextStyle(fontSize: 10, color: EzizaColors.kMuted)),
                ],
              ],
            )),
            const SizedBox(width: 8),
            _statusChip(pin),
          ]),
        );
      }),
    ]);
  }

  Widget _statusChip(_RiderPin pin) {
    if (!pin.online) {
      return _chip('Offline', const Color(0xFFF5F5F5), EzizaColors.kMuted);
    }
    if (pin.stale) {
      final mins  = pin.staleFor?.inMinutes;
      final label = mins != null ? 'Last ${mins}m ago' : 'Stale';
      return _chip(label, const Color(0xFFFFF8E1), EzizaColors.kGold);
    }
    return _chip('Online', const Color(0xFFDCFCE7), EzizaColors.kSuccess);
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(10)),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
  );
}

// ── Model ─────────────────────────────────────────────────────────────────────

class _RiderPin {
  final LatLng       location;
  final String       name;
  final bool         online;
  final Color        color;
  final bool         stale;
  final Duration?    staleFor;
  final String?      phase;
  final LatLng?      destination;
  final String?      destinationLabel;
  final String?      destinationAddress;
  final List<LatLng> routePoints;

  const _RiderPin({
    required this.location,
    required this.name,
    required this.online,
    required this.color,
    this.stale              = false,
    this.staleFor,
    this.phase,
    this.destination,
    this.destinationLabel,
    this.destinationAddress,
    this.routePoints        = const [],
  });
}
