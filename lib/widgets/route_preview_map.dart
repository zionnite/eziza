import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../constants/colors.dart';

/// Small, interactive-but-static-feeling map preview showing the pickup and
/// drop-off pins for a delivery. Used before a rider/company commits to an
/// offer so they can actually see where the job is and roughly how far
/// apart the two points are, instead of committing off two lines of
/// address text.
class RoutePreviewMap extends StatelessWidget {
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final double height;

  const RoutePreviewMap({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(pickupLat, pickupLng);
    final dropoff = LatLng(dropoffLat, dropoffLng);
    final bounds = LatLngBounds.fromPoints([pickup, dropoff]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.fromLTRB(36, 36, 36, 36),
                maxZoom: 15,
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.eziza.rider',
              ),
              PolylineLayer(polylines: [
                Polyline(
                  points: [pickup, dropoff],
                  strokeWidth: 3,
                  color: EzizaColors.kPurple.withValues(alpha: 0.5),
                ),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: pickup,
                  width: 36,
                  height: 44,
                  child: _pin(EzizaColors.kGold, Icons.store_rounded),
                ),
                Marker(
                  point: dropoff,
                  width: 36,
                  height: 44,
                  child: _pin(EzizaColors.kPurple, Icons.home_rounded),
                ),
              ]),
            ],
          ),
          // Legend
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _legendDot(EzizaColors.kGold),
                const SizedBox(width: 4),
                const Text('Pickup',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: EzizaColors.kText)),
                const SizedBox(width: 10),
                _legendDot(EzizaColors.kPurple),
                const SizedBox(width: 4),
                const Text('Drop-off',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: EzizaColors.kText)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pin(Color color, IconData icon) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)],
          ),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        Container(width: 2, height: 8, color: color),
      ]);

  Widget _legendDot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
