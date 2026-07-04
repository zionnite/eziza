import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../constants/colors.dart';

// Nigeria centre — shown when device location is unavailable
const _ngDefault = LatLng(9.0820, 8.6753);

typedef LocationResult = ({String address, double lat, double lng, String state});

class LocationPickerSheet extends StatefulWidget {
  final String title;
  final String subtitle;

  const LocationPickerSheet({
    super.key,
    required this.title,
    required this.subtitle,
  });

  static Future<LocationResult?> pick({
    required String title,
    String subtitle = 'Drag the pin to the exact location',
  }) {
    return Get.bottomSheet<LocationResult>(
      LocationPickerSheet(title: title, subtitle: subtitle),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final _mapCtrl     = MapController();
  final _stateCtrl   = TextEditingController();
  final _cityCtrl    = TextEditingController();
  final _streetCtrl  = TextEditingController();
  final _landmarkCtrl = TextEditingController();

  final List<String> _landmarks = [];

  LatLng? _pin;
  bool    _locating         = false;
  bool    _reversing        = false;
  bool    _forwarding       = false;
  bool    _forwardNotFound  = false;
  bool    _mapExpanded      = false;
  bool    _suppressListeners = false;

  Timer? _reverseDebounce;
  Timer? _forwardDebounce;

  @override
  void initState() {
    super.initState();
    _stateCtrl.addListener(_onFieldChanged);
    _cityCtrl.addListener(_onFieldChanged);
    _useCurrentLocation();
  }

  @override
  void dispose() {
    _stateCtrl.dispose();
    _cityCtrl.dispose();
    _streetCtrl.dispose();
    _landmarkCtrl.dispose();
    _reverseDebounce?.cancel();
    _forwardDebounce?.cancel();
    super.dispose();
  }

  // ── GPS ──────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          Get.snackbar('Permission needed',
              'Enable location to auto-fill your address',
              backgroundColor: Colors.black,
              colorText: Colors.white,
              snackPosition: SnackPosition.BOTTOM,
              margin: const EdgeInsets.all(16));
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));

      final loc = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _pin = loc);
        _mapCtrl.move(loc, 17);
        _scheduleReverseGeocode(loc);
      }
    } catch (_) {
      if (mounted) {
        Get.snackbar('Could not get location',
            'Drag the pin on the map to your exact location',
            backgroundColor: Colors.black,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
            margin: const EdgeInsets.all(16));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Forward geocode (fields → map) ───────────────────────────

  void _onFieldChanged() {
    if (_suppressListeners) return;
    _forwardDebounce?.cancel();
    _forwardDebounce = Timer(
      const Duration(milliseconds: 1500),
      _forwardGeocode,
    );
  }

  Future<void> _forwardGeocode() async {
    if (!mounted) return;
    final state  = _stateCtrl.text.trim();
    final city   = _cityCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    if (state.isEmpty) return;

    setState(() { _forwarding = true; _forwardNotFound = false; });

    final parts = [
      if (street.isNotEmpty) street,
      if (city.isNotEmpty)   city,
      state,
      'Nigeria',
    ];
    final zoom = street.isNotEmpty ? 16.0 : city.isNotEmpty ? 14.0 : 10.0;

    bool found = false;
    try {
      final query = Uri.encodeComponent(parts.join(', '));
      final url   = 'https://nominatim.openstreetmap.org/search'
          '?format=json&q=$query&limit=1';
      final resp  = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'EzizaRider/1.0'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final list = jsonDecode(resp.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final lat = double.tryParse(list[0]['lat']?.toString() ?? '');
          final lng = double.tryParse(list[0]['lon']?.toString() ?? '');
          if (lat != null && lng != null) {
            final loc = LatLng(lat, lng);
            setState(() => _pin = loc);
            _mapCtrl.move(loc, zoom);
            found = true;
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() { _forwarding = false; _forwardNotFound = !found; });
    }
  }

  // ── Reverse geocode (map → fields) ───────────────────────────

  void _onMapMoveEnd(MapCamera camera) {
    _forwardDebounce?.cancel();
    final loc = camera.center;
    setState(() { _pin = loc; _forwardNotFound = false; });
    _scheduleReverseGeocode(loc);
  }

  void _scheduleReverseGeocode(LatLng loc) {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 600), () {
      _reverseGeocode(loc.latitude, loc.longitude);
    });
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _reversing = true);
    try {
      final url = 'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1';
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'EzizaRider/1.0'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        final state = addr['state'] as String?;
        final city  = addr['city']        as String?
            ?? addr['town']              as String?
            ?? addr['village']           as String?
            ?? addr['city_district']     as String?
            ?? addr['suburb']            as String?;
        final houseNum = addr['house_number'] as String?;
        final roadName = addr['road']         as String?;
        final road     = roadName
            ?? addr['pedestrian']        as String?
            ?? addr['footway']           as String?
            ?? addr['path']              as String?
            ?? addr['street']            as String?
            ?? (houseNum != null ? '$houseNum ${roadName ?? ''}'.trim() : null)
            ?? addr['neighbourhood']     as String?;

        _suppressListeners = true;
        if (state != null) _stateCtrl.text  = state;
        if (city  != null) _cityCtrl.text   = city;
        if (road  != null && road.isNotEmpty) _streetCtrl.text = road;
        _suppressListeners = false;
        if (mounted) setState(() => _forwardNotFound = false);
      }
    } catch (_) {}
    if (mounted) setState(() => _reversing = false);
  }

  // ── Confirm ───────────────────────────────────────────────────

  void _confirm() {
    if (_pin == null) {
      Get.snackbar('Pin your location',
          'Tap "Use my location" or drag the map to set your position',
          backgroundColor: Colors.black,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16));
      return;
    }

    final state  = _stateCtrl.text.trim();
    final city   = _cityCtrl.text.trim();
    final street = _streetCtrl.text.trim();

    if (state.isEmpty || city.isEmpty || street.isEmpty) {
      Get.snackbar('Incomplete',
          'Please fill in State, City and Street Address',
          backgroundColor: Colors.black,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16));
      return;
    }

    final parts = <String>[street];
    if (_landmarks.isNotEmpty) parts.add('(Near: ${_landmarks.join(', ')})');
    parts.add(city);
    parts.add(state);
    final full = parts.join(', ');

    Get.back(result: (address: full, lat: _pin!.latitude, lng: _pin!.longitude, state: state));
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.93),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          decoration: BoxDecoration(
            color: EzizaColors.kBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EzizaColors.kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_outlined,
                  size: 18, color: EzizaColors.kPurpleD),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: EzizaColors.kText)),
                  Text(widget.subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: EzizaColors.kMuted)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => Get.back(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: EzizaColors.kBorder),

        // Scrollable body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Map picker ────────────────────────────────
                _buildMapPicker(),
                const SizedBox(height: 12),

                // ── Use my location button ────────────────────
                GestureDetector(
                  onTap: _locating ? null : _useCurrentLocation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 11, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: EzizaColors.kGold.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      _locating
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFD97706)))
                          : const Icon(Icons.my_location_rounded,
                              color: Color(0xFFD97706), size: 16),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Use my current location',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E))),
                      ),
                      if (_pin != null)
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF16A34A), size: 16),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),

                if (_forwardNotFound)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFFD966).withValues(alpha: 0.6)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded,
                          size: 13, color: Color(0xFF856404)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Address not found on map — drag the pin to your exact location',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF856404),
                              height: 1.3),
                        ),
                      ),
                    ]),
                  )
                else
                  const Text(
                    'Or drag the map above to pin your exact location',
                    style: TextStyle(fontSize: 11, color: EzizaColors.kMuted),
                  ),
                const SizedBox(height: 16),

                // ── Address fields header ─────────────────────
                Row(children: [
                  const Icon(Icons.edit_location_alt_rounded,
                      size: 14, color: EzizaColors.kPurple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _reversing ? 'Filling from map…'
                          : _forwarding ? 'Finding on map…'
                          : 'Review and complete the address',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: (_reversing || _forwarding)
                              ? EzizaColors.kMuted
                              : EzizaColors.kText),
                    ),
                  ),
                  if (_reversing || _forwarding)
                    const SizedBox(
                      width: 10, height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: EzizaColors.kPurple),
                    )
                  else
                    GestureDetector(
                      onTap: () {
                        _forwardDebounce?.cancel();
                        _forwardGeocode();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: EzizaColors.kPurple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(children: [
                          Icon(Icons.search_rounded,
                              size: 12, color: EzizaColors.kPurpleD),
                          SizedBox(width: 4),
                          Text('Find on map',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: EzizaColors.kPurpleD,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ]),
                const SizedBox(height: 10),

                // Fields
                _label('State'),
                _field(controller: _stateCtrl,
                    hint: 'e.g. Lagos', icon: Icons.map_outlined),
                const SizedBox(height: 12),
                _label('City / Area'),
                _field(controller: _cityCtrl,
                    hint: 'e.g. Lekki', icon: Icons.location_city_outlined),
                const SizedBox(height: 12),
                _label('Street Address'),
                _field(controller: _streetCtrl,
                    hint: 'e.g. 12 Bode Thomas Street',
                    icon: Icons.home_outlined,
                    maxLines: 2),
                const SizedBox(height: 12),

                // ── Landmarks ─────────────────────────────────
                _label('Landmarks (optional)'),
                const Text(
                  'Add nearby landmarks to help the rider find the location',
                  style: TextStyle(fontSize: 11, color: EzizaColors.kMuted),
                ),
                const SizedBox(height: 8),

                if (_landmarks.isNotEmpty) ...[
                  Wrap(
                    spacing: 8, runSpacing: 6,
                    children: _landmarks.asMap().entries.map((e) =>
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.place_outlined,
                              color: Colors.white70, size: 12),
                          const SizedBox(width: 4),
                          Text(e.value,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(
                                () => _landmarks.removeAt(e.key)),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white70, size: 12),
                          ),
                        ]),
                      ),
                    ).toList(),
                  ),
                  const SizedBox(height: 8),
                ],

                Row(children: [
                  Expanded(
                    child: _field(
                        controller: _landmarkCtrl,
                        hint: 'e.g. First Bank ATM, Shoprite',
                        icon: Icons.place_outlined),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      final lm = _landmarkCtrl.text.trim();
                      if (lm.isEmpty) return;
                      setState(() {
                        _landmarks.add(lm);
                        _landmarkCtrl.clear();
                      });
                    },
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(children: [
                        Icon(Icons.add_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 4),
                        Text('Add',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // ── Confirm button ─────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: EzizaColors.kBorder)),
          ),
          child: GestureDetector(
            onTap: _confirm,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Use This Location',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Map picker widget ─────────────────────────────────────────

  Widget _buildMapPicker() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: _mapExpanded ? 380 : 210,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(alignment: Alignment.center, children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _pin ?? _ngDefault,
              initialZoom:   _pin != null ? 17 : 6,
              onMapEvent: (event) {
                if (event is MapEventMoveEnd &&
                    event.source != MapEventSource.mapController) {
                  _onMapMoveEnd(event.camera);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.eziza.rider',
              ),
            ],
          ),

          // Fixed centre pin
          const IgnorePointer(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_pin,
                  color: EzizaColors.kPurpleD, size: 44),
              SizedBox(
                width: 10, height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x336C3483),
                    borderRadius:
                        BorderRadius.all(Radius.elliptical(5, 2)),
                  ),
                ),
              ),
            ]),
          ),

          // Drag hint
          Positioned(
            top: 8, left: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6),
                  ],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_with_rounded,
                      size: 12, color: EzizaColors.kPurpleD),
                  SizedBox(width: 4),
                  Text('Drag to pin location',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: EzizaColors.kPurpleD)),
                ]),
              ),
            ),
          ),

          // Expand / collapse
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () => setState(() => _mapExpanded = !_mapExpanded),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6),
                  ],
                ),
                child: Icon(
                  _mapExpanded
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  size: 18, color: EzizaColors.kPurpleD,
                ),
              ),
            ),
          ),

          // Zoom controls
          Positioned(
            bottom: 8, left: 8,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _zoomBtn(Icons.add_rounded, () {
                final z =
                    (_mapCtrl.camera.zoom + 1).clamp(1.0, 19.0);
                _mapCtrl.move(_mapCtrl.camera.center, z);
              }),
              const SizedBox(height: 4),
              _zoomBtn(Icons.remove_rounded, () {
                final z =
                    (_mapCtrl.camera.zoom - 1).clamp(1.0, 19.0);
                _mapCtrl.move(_mapCtrl.camera.center, z);
              }),
            ]),
          ),

          // GPS coords badge
          if (_pin != null)
            Positioned(
              bottom: 8, right: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4),
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.gps_fixed,
                        size: 10, color: Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Text(
                      '${_pin!.latitude.toStringAsFixed(5)}, '
                      '${_pin!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF166534)),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08), blurRadius: 4),
            ],
          ),
          child: Icon(icon, size: 18, color: EzizaColors.kPurpleD),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EzizaColors.kText)),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [
            BoxShadow(
                color: EzizaColors.kPurple.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1)),
          ],
        ),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14, color: EzizaColors.kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: EzizaColors.kMuted, fontSize: 13),
            prefixIcon: Padding(
              padding: maxLines > 1
                  ? const EdgeInsets.only(bottom: 20)
                  : EdgeInsets.zero,
              child: Icon(icon, color: EzizaColors.kPurple, size: 18),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      );
}
