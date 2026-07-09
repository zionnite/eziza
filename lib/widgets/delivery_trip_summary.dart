import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import 'route_preview_map.dart';

Future<void> _callPhone(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched) {
    Get.snackbar('Could not open dialler', 'Try dialling $phone manually.',
        backgroundColor: EzizaColors.kError,
        colorText: EzizaColors.kWhite,
        snackPosition: SnackPosition.BOTTOM);
  }
}

double _distKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

String _fmtKm(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

/// Uber/Bolt-style trip summary shown before committing to an offer: full
/// pickup/drop-off addresses on a route timeline, a map preview, trip and
/// (for a rider, if their live location is known) rider-to-pickup distance,
/// and sender/receiver contact cards with a tap-to-call button. Shared
/// between rider_dashboard_page.dart and company_dashboard_page.dart's
/// offer sheets so both look and behave identically.
class DeliveryTripSummary extends StatelessWidget {
  final Map<String, dynamic> delivery;
  final double? riderLat;
  final double? riderLng;

  const DeliveryTripSummary({
    super.key,
    required this.delivery,
    this.riderLat,
    this.riderLng,
  });

  @override
  Widget build(BuildContext context) {
    final pickupAddr  = delivery['pickup_address']   as String? ?? 'Pickup address unavailable';
    final dropoffAddr = delivery['delivery_address'] as String? ?? 'Drop-off address unavailable';
    final pLat = (delivery['pickup_lat']   as num?)?.toDouble();
    final pLng = (delivery['pickup_lng']   as num?)?.toDouble();
    final dLat = (delivery['delivery_lat'] as num?)?.toDouble();
    final dLng = (delivery['delivery_lng'] as num?)?.toDouble();
    final hasCoords = pLat != null && pLng != null && dLat != null && dLng != null;

    final tripKm = hasCoords ? _distKm(pLat, pLng, dLat, dLng) : null;
    final riderToPickupKm = (riderLat != null && riderLng != null && pLat != null && pLng != null)
        ? _distKm(riderLat!, riderLng!, pLat, pLng)
        : null;

    final senderName   = (delivery['pickup_contact_name']    as String?)?.trim();
    final senderPhone  = (delivery['pickup_contact_phone']   as String?)?.trim();
    final receiverName = (delivery['delivery_contact_name']  as String?)?.trim();
    final receiverPhone = (delivery['delivery_contact_phone'] as String?)?.trim();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Route: pickup + drop-off, Uber/Bolt-style timeline ──────
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(color: EzizaColors.kGold, shape: BoxShape.circle),
          ),
          Container(width: 2, height: 34, color: EzizaColors.kBorder),
          Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(color: EzizaColors.kPurple, shape: BoxShape.circle),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pickupAddr,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: EzizaColors.kText, height: 1.3)),
            const SizedBox(height: 22),
            Text(dropoffAddr,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: EzizaColors.kText, height: 1.3)),
          ]),
        ),
      ]),

      const SizedBox(height: 16),

      if (hasCoords)
        RoutePreviewMap(pickupLat: pLat, pickupLng: pLng, dropoffLat: dLat, dropoffLng: dLng)
      else
        Container(
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: EzizaColors.kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EzizaColors.kBorder)),
          child: const Text('Map preview unavailable for this delivery',
              style: TextStyle(fontSize: 12, color: EzizaColors.kMuted)),
        ),

      if (tripKm != null || riderToPickupKm != null) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (tripKm != null)
            _distancePill(Icons.social_distance_rounded, 'Trip distance', _fmtKm(tripKm), EzizaColors.kPurpleD),
          if (riderToPickupKm != null)
            _distancePill(Icons.near_me_rounded, 'You → Pickup', _fmtKm(riderToPickupKm), EzizaColors.kGold),
        ]),
      ],

      if (senderName != null || senderPhone != null || receiverName != null || receiverPhone != null) ...[
        const SizedBox(height: 14),
        if (senderName != null || senderPhone != null)
          _contactCard(
            role: 'Sender', icon: Icons.store_rounded, color: EzizaColors.kGold,
            name: senderName, phone: senderPhone,
          ),
        if ((senderName != null || senderPhone != null) && (receiverName != null || receiverPhone != null))
          const SizedBox(height: 8),
        if (receiverName != null || receiverPhone != null)
          _contactCard(
            role: 'Receiver', icon: Icons.home_rounded, color: EzizaColors.kPurple,
            name: receiverName, phone: receiverPhone,
          ),
      ],
    ]);
  }

  Widget _distancePill(IconData icon, String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _contactCard({
    required String role,
    required IconData icon,
    required Color color,
    String? name,
    String? phone,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(role,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.6)),
            const SizedBox(height: 1),
            Text(
              (name == null || name.isEmpty) ? (phone ?? 'No contact on file') : name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: EzizaColors.kText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        if (phone != null && phone.isNotEmpty)
          GestureDetector(
            onTap: () => _callPhone(phone),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const Icon(Icons.phone_rounded, size: 15, color: Colors.white),
            ),
          ),
      ]),
    );
  }
}
