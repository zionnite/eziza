import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import 'customer_delivery_detail_page.dart';
import 'send_package_page.dart';

class MyDeliveriesPage extends StatefulWidget {
  const MyDeliveriesPage({super.key});

  @override
  State<MyDeliveriesPage> createState() => _MyDeliveriesPageState();
}

class _MyDeliveriesPageState extends State<MyDeliveriesPage> {
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        setState(() => _loading = false);
        return;
      }
      final res = await _db
          .from('deliveries')
          .select()
          .eq('customer_id', uid)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _deliveries = List<Map<String, dynamic>>.from(res);
          _loading    = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: EzizaColors.kPurpleD))
              : _deliveries.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      color: EzizaColors.kPurpleD,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _deliveries.length,
                        separatorBuilder: (_, i) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _deliveryCard(_deliveries[i]),
                      ),
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Get.to(() => const SendPackagePage());
          _load();
        },
        backgroundColor: EzizaColors.kPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Send Package',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 4,
      ),
    );
  }

  Widget _buildHeader() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
                color: Color(0x556C3483),
                blurRadius: 14,
                offset: Offset(0, 5))
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            child: Row(children: [
              GestureDetector(
                onTap: Get.back,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1))),
                  child: const Icon(Icons.arrow_back_ios_new,
                      size: 16, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('My Deliveries',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(
                    '${_deliveries.length} request${_deliveries.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54),
                  ),
                ]),
              ),
              GestureDetector(
                onTap: _load,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.refresh_rounded,
                      size: 18, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: EzizaColors.kPurple.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.local_shipping_outlined,
                  size: 48, color: EzizaColors.kPurple),
            ),
            const SizedBox(height: 20),
            const Text('No deliveries yet',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: EzizaColors.kText)),
            const SizedBox(height: 8),
            const Text(
              'Tap the button below to request\nyour first delivery.',
              style: TextStyle(
                  fontSize: 13,
                  color: EzizaColors.kMuted,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _deliveryCard(Map<String, dynamic> d) {
    final status    = d['status'] as String? ?? 'open';
    final pickup    = d['pickup_address']   as String? ?? '';
    final delivery  = d['delivery_address'] as String? ?? '';
    final createdAt = DateTime.tryParse(d['created_at'] as String? ?? '');
    final price     = (d['agreed_price'] as num?)?.toDouble();
    final desc      = d['package_description'] as String? ?? '';

    return GestureDetector(
      onTap: () async {
        await Get.to(
          () => CustomerDeliveryDetailPage(deliveryId: d['id'] as String),
        );
        _load();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EzizaColors.kBorder),
            boxShadow: [
              BoxShadow(
                  color: EzizaColors.kPurple.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Top row: date + status
          Row(children: [
            Expanded(
              child: Text(
                createdAt != null ? _fmtDate(createdAt) : '',
                style: const TextStyle(
                    fontSize: 11, color: EzizaColors.kMuted),
              ),
            ),
            _statusChip(status),
          ]),
          const SizedBox(height: 12),

          // Route
          _routeRow(Icons.radio_button_checked,
              EzizaColors.kPurple, _shortAddr(pickup)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 0, 4),
            child: Container(
                width: 2, height: 14, color: EzizaColors.kBorder),
          ),
          _routeRow(Icons.location_on_rounded,
              EzizaColors.kGold, _shortAddr(delivery)),

          if (desc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(desc,
                style: const TextStyle(
                    fontSize: 12, color: EzizaColors.kMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],

          if (price != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: EzizaColors.kSuccess
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: EzizaColors.kSuccess
                          .withValues(alpha: 0.2))),
              child: Text('₦${price.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: EzizaColors.kSuccess)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label) => Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EzizaColors.kText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );

  Widget _statusChip(String status) {
    final (Color text, Color bg) = switch (status) {
      'open'      => (EzizaColors.kPurpleD,         const Color(0xFFF3E5F5)),
      'assigned'  => (const Color(0xFF0284C7),       const Color(0xFFE0F2FE)),
      'picked_up' => (EzizaColors.kGold,             const Color(0xFFFFF8E1)),
      'delivered' => (EzizaColors.kSuccess,          const Color(0xFFDCFCE7)),
      'confirmed' => (EzizaColors.kSuccess,          const Color(0xFFDCFCE7)),
      'cancelled' => (EzizaColors.kError,            const Color(0xFFFFEBEE)),
      _           => (EzizaColors.kMuted,            const Color(0xFFF5F5F5)),
    };
    final label = switch (status) {
      'open'      => 'Open',
      'assigned'  => 'Assigned',
      'picked_up' => 'In Transit',
      'delivered' => 'Delivered',
      'confirmed' => 'Complete',
      'cancelled' => 'Cancelled',
      _           => status,
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: text)),
    );
  }

  String _shortAddr(String addr) {
    if (addr.isEmpty) return '—';
    final comma = addr.indexOf(',');
    final raw   = comma == -1 ? addr : addr.substring(0, comma);
    return raw.length > 28 ? '${raw.substring(0, 25)}…' : raw;
  }

  String _fmtDate(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Today $h:$m';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else {
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month]}';
    }
  }
}
