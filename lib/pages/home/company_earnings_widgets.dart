import 'package:flutter/material.dart';

import '../../constants/colors.dart';

// Shared card widgets for the company Earnings tab and its "View All" detail
// pages, so the preview list and full history stay visually identical
// without duplicating the rendering logic in three places.

String shortAddr(String addr) {
  if (addr.isEmpty) return '—';
  final parts = addr.split(',');
  return parts.first.trim().length > 22
      ? '${parts.first.trim().substring(0, 22)}…'
      : parts.first.trim();
}

Widget companyEarningsHistoryCard(Map<String, dynamic> d) {
  final gross    = (d['agreed_price']  as num?)?.toDouble() ?? 0;
  final fee      = (d['platform_fee']  as num?)?.toDouble() ?? 0;
  final net      = gross - fee;
  final pickup   = d['pickup_address']   as String? ?? '';
  final delivery = d['delivery_address'] as String? ?? '';
  final date     = d['confirmed_at'] as String? ?? d['created_at'] as String? ?? '';
  final dateLabel = date.length >= 10 ? date.substring(0, 10) : date;
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: EzizaColors.kWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EzizaColors.kBorder)),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: EzizaColors.kSuccess.withValues(alpha: 0.1),
            shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded,
            size: 16, color: EzizaColors.kSuccess),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('${shortAddr(pickup)} → ${shortAddr(delivery)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EzizaColors.kText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(dateLabel,
              style: const TextStyle(
                  fontSize: 11, color: EzizaColors.kMuted)),
        ]),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('₦${net.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: EzizaColors.kText)),
          if (fee > 0)
            Text('–₦${fee.toStringAsFixed(0)} fee',
                style: const TextStyle(
                    color: EzizaColors.kMuted, fontSize: 11)),
        ],
      ),
    ]),
  );
}

Widget companyPayoutHistoryCard(Map<String, dynamic> p) {
  final status = p['status'] as String? ?? 'pending';
  final amount = (p['amount'] as num?)?.toDouble() ?? 0;
  final reqAt  = p['requested_at'] != null
      ? DateTime.tryParse(p['requested_at'].toString())?.toLocal()
      : null;
  final procAt = p['processed_at'] != null
      ? DateTime.tryParse(p['processed_at'].toString())?.toLocal()
      : null;

  final (Color sc, Color sbg, IconData sicon, String slabel) =
      switch (status) {
    'pending'  => (EzizaColors.kGold,              const Color(0xFFFFF8E1), Icons.hourglass_top_rounded,          'Pending'),
    'approved' => (const Color(0xFF0284C7),         const Color(0xFFE0F2FE), Icons.check_circle_outline_rounded,   'Approved'),
    'paid'     => (EzizaColors.kSuccess,            const Color(0xFFDCFCE7), Icons.payments_rounded,               'Paid'),
    'rejected' => (EzizaColors.kError,              const Color(0xFFFFEDED), Icons.cancel_outlined,                'Rejected'),
    _          => (EzizaColors.kMuted,              const Color(0xFFF5F5F5), Icons.info_outline_rounded,            status),
  };

  String fmt(DateTime? dt) =>
      dt != null ? '${dt.day}/${dt.month}/${dt.year}' : '';

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: EzizaColors.kWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EzizaColors.kBorder),
        boxShadow: [
          BoxShadow(
              color: EzizaColors.kPurple.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ]),
    child: Row(children: [
      Container(
          padding: const EdgeInsets.all(9),
          decoration:
              BoxDecoration(color: sbg, shape: BoxShape.circle),
          child: Icon(sicon, color: sc, size: 16)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('₦${amount.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: EzizaColors.kText)),
          const SizedBox(height: 2),
          Text(
            reqAt != null
                ? 'Requested ${fmt(reqAt)}'
                    '${procAt != null ? '  ·  Processed ${fmt(procAt)}' : ''}'
                : '',
            style: const TextStyle(
                fontSize: 11, color: EzizaColors.kMuted),
          ),
        ]),
      ),
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: sbg, borderRadius: BorderRadius.circular(20)),
        child: Text(slabel,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: sc)),
      ),
    ]),
  );
}
