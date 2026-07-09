import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../constants/colors.dart';
import '../../controllers/delivery_controller.dart';
import '../../models/delivery.dart';
import '../../services/location_service.dart';
import '../../services/nominatim_service.dart';
import '../../utils/currency.dart';

// ── Page ──────────────────────────────────────────────────────

class ActiveDeliveryPage extends StatefulWidget {
  const ActiveDeliveryPage({super.key});

  @override
  State<ActiveDeliveryPage> createState() => _ActiveDeliveryPageState();
}

class _ActiveDeliveryPageState extends State<ActiveDeliveryPage> {
  final _ctrl          = Get.find<DeliveryController>();
  final _mapController = MapController();

  LatLng? _pickupPin;
  LatLng? _dropoffPin;
  LatLng? _riderPos;
  bool    _centeredOnRider = false;

  StreamSubscription<Position>? _posSub;

  static const _lagosFallback = LatLng(6.5244, 3.3792);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final delivery = _ctrl.activeDelivery.value;
    if (delivery != null) _loadPins(delivery);

    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission || !mounted) return;

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() => _riderPos = latlng);
      if (!_centeredOnRider) {
        _mapController.move(latlng, 15);
        _centeredOnRider = true;
      }
    });
  }

  Future<void> _loadPins(Delivery delivery) async {
    final pickup = (delivery.pickupLat != null && delivery.pickupLng != null)
        ? LatLng(delivery.pickupLat!, delivery.pickupLng!)
        : await NominatimService.geocode(delivery.pickupAddress);

    final dropoff =
        (delivery.deliveryLat != null && delivery.deliveryLng != null)
            ? LatLng(delivery.deliveryLat!, delivery.deliveryLng!)
            : await NominatimService.geocode(delivery.deliveryAddress);

    if (mounted) setState(() { _pickupPin = pickup; _dropoffPin = dropoff; });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        final delivery = _ctrl.activeDelivery.value;
        if (delivery == null) {
          return const Center(child: Text('No active delivery'));
        }
        return Column(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.42,
              child: _buildMap(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _StatusCard(delivery: delivery),
                  const SizedBox(height: 12),
                  _InfoCard(delivery: delivery),
                  const SizedBox(height: 20),
                  _ActionButton(delivery: delivery),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  // ── Map ────────────────────────────────────────────────────

  Widget _buildMap() {
    final center = _riderPos ?? _pickupPin ?? _lagosFallback;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.eziza.rider',
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        // ── Back button overlay ─────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Material(
              color: EzizaColors.kWhite,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Get.back(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.arrow_back_ios_rounded,
                      size: 18, color: EzizaColors.kText),
                ),
              ),
            ),
          ),
        ),
        // ── Recenter button ─────────────────────────────────
        Positioned(
          bottom: 12, right: 12,
          child: Material(
            color: EzizaColors.kWhite,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                if (_riderPos != null) _mapController.move(_riderPos!, 15);
              },
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.my_location_rounded,
                    color: EzizaColors.kPurple, size: 20),
              ),
            ),
          ),
        ),
        // ── Legend ──────────────────────────────────────────
        Positioned(
          bottom: 12, left: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: EzizaColors.kWhite.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _legendRow(EzizaColors.kPurple, 'Pickup'),
                const SizedBox(height: 4),
                _legendRow(EzizaColors.kGold, 'Drop-off'),
                const SizedBox(height: 4),
                _legendRow(EzizaColors.kTeal, 'You'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: EzizaColors.kText)),
        ],
      );

  List<Marker> _buildMarkers() => [
        if (_pickupPin != null)
          Marker(
            point: _pickupPin!,
            width: 40, height: 52,
            alignment: Alignment.bottomCenter,
            child: _PinWidget(
                color: EzizaColors.kPurple,
                icon: Icons.storefront_rounded),
          ),
        if (_dropoffPin != null)
          Marker(
            point: _dropoffPin!,
            width: 40, height: 52,
            alignment: Alignment.bottomCenter,
            child: _PinWidget(
                color: EzizaColors.kGold,
                icon: Icons.home_rounded),
          ),
        if (_riderPos != null)
          Marker(
            point: _riderPos!,
            width: 26, height: 26,
            child: const _RiderDot(),
          ),
      ];
}

// ── Map markers ───────────────────────────────────────────────

class _PinWidget extends StatelessWidget {
  final Color    color;
  final IconData icon;
  const _PinWidget({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: Icon(icon, color: EzizaColors.kWhite, size: 18),
          ),
          Container(width: 2, height: 12, color: color),
        ],
      );
}

class _RiderDot extends StatelessWidget {
  const _RiderDot();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: EzizaColors.kTeal,
          shape: BoxShape.circle,
          border: Border.all(color: EzizaColors.kWhite, width: 3),
          boxShadow: [
            BoxShadow(
              color: EzizaColors.kTeal.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 2,
            )
          ],
        ),
      );
}

// ── Status stepper ────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final Delivery delivery;
  const _StatusCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    const steps = [
      'assigned',
      'awaiting_pickup_confirm',
      'picked_up',
      'delivered',
      'confirmed',
    ];
    final current = steps.indexOf(delivery.status);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EzizaColors.kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delivery Status',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: EzizaColors.kText)),
            const SizedBox(height: 16),
            ...steps.asMap().entries.map((e) {
              final idx  = e.key;
              final done = idx <= current;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: done
                          ? EzizaColors.kPurple
                          : EzizaColors.kBorder,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check : Icons.circle_outlined,
                      color: EzizaColors.kWhite,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _label(e.value),
                    style: TextStyle(
                        color: done
                            ? EzizaColors.kText
                            : EzizaColors.kMuted,
                        fontWeight: idx == current
                            ? FontWeight.bold
                            : FontWeight.normal),
                  ),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _label(String s) => switch (s) {
        'assigned'               => 'Assigned — Head to pickup',
        'awaiting_pickup_confirm' => 'Awaiting merchant handoff',
        'picked_up'              => 'Package picked up — En route',
        'delivered'              => 'Delivered — Awaiting confirmation',
        'confirmed'              => 'Confirmed — Complete',
        _                        => s,
      };
}

// ── Delivery details card ─────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final Delivery delivery;
  const _InfoCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EzizaColors.kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delivery Details',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: EzizaColors.kText)),
            const SizedBox(height: 12),
            _Row(label: 'Pickup', value: delivery.pickupAddress),
            if (delivery.pickupContactPhone != null)
              _Row(
                  label: 'Merchant phone',
                  value: delivery.pickupContactPhone!),
            const Divider(height: 20),
            _Row(label: 'Drop-off', value: delivery.deliveryAddress),
            if (delivery.deliveryContactPhone != null)
              _Row(
                  label: 'Customer phone',
                  value: delivery.deliveryContactPhone!),
            if (delivery.agreedPrice != null) ...[
              const Divider(height: 20),
              _Row(
                label: 'Your earnings',
                value: formatNaira(delivery.agreedPrice!),
                highlight: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool   highlight;
  const _Row(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(
                      color: EzizaColors.kMuted, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      color: highlight
                          ? EzizaColors.kPurple
                          : EzizaColors.kText,
                      fontSize: 13,
                      fontWeight: highlight
                          ? FontWeight.bold
                          : FontWeight.normal)),
            ),
          ],
        ),
      );
}

// ── Action button ─────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final Delivery delivery;
  const _ActionButton({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DeliveryController>();
    final next = _nextStatus(delivery.status);
    if (next == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: EzizaColors.kPurple,
          foregroundColor: EzizaColors.kWhite,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(_actionLabel(delivery.status)),
              content: Text(
                  'Mark this as ${_statusLabel(next)}?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirm')),
              ],
            ),
          );
          if (confirmed != true) return;
          final result =
              await ctrl.updateStatus(delivery.id, next);
          if (result != 'true') {
            Get.snackbar('Error', result,
                backgroundColor: EzizaColors.kError,
                colorText: EzizaColors.kWhite);
          }
        },
        child: Text(_actionLabel(delivery.status),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  String? _nextStatus(String s) => switch (s) {
        'assigned'               => 'awaiting_pickup_confirm',
        'awaiting_pickup_confirm' => 'picked_up',
        'picked_up'              => 'delivered',
        _                        => null,
      };

  String _actionLabel(String s) => switch (s) {
        'assigned'               => "Notify Merchant — I've Arrived",
        'awaiting_pickup_confirm' => 'Confirm Package Received',
        'picked_up'              => 'Mark as Delivered',
        _                        => '',
      };

  String _statusLabel(String s) => switch (s) {
        'awaiting_pickup_confirm' => 'awaiting pickup',
        'picked_up'              => 'picked up',
        'delivered'              => 'delivered',
        _                        => s,
      };
}
