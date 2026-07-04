import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import 'delivery_tracking_page.dart';

class CustomerDeliveryDetailPage extends StatefulWidget {
  const CustomerDeliveryDetailPage({
    super.key,
    required this.deliveryId,
    this.isRecipient = false,
  });
  final String deliveryId;
  final bool isRecipient;

  @override
  State<CustomerDeliveryDetailPage> createState() =>
      _CustomerDeliveryDetailPageState();
}

class _CustomerDeliveryDetailPageState
    extends State<CustomerDeliveryDetailPage> {
  final _db = Supabase.instance.client;

  Map<String, dynamic>? _delivery;
  List<Map<String, dynamic>> _bids = [];
  bool _loading    = true;
  bool _accepting  = false;
  bool _confirming = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _db
          .from('deliveries')
          .select()
          .eq('id', widget.deliveryId)
          .single();
      if (mounted) _delivery = Map<String, dynamic>.from(d);
    } catch (_) {}

    try {
      final bidsRes = await _db
          .from('delivery_bids')
          .select(
              '*, '
              'rider:riders(id, full_name, vehicle_type, rating_avg, phone), '
              'company:companies(id, name, rating_avg, phone)')
          .eq('delivery_id', widget.deliveryId)
          .order('amount', ascending: true);
      if (mounted) _bids = List<Map<String, dynamic>>.from(bidsRes);
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    if (_channel != null) {
      _db.removeChannel(_channel!);
      _channel = null;
    }
    _channel = _db
        .channel('cust_detail_${widget.deliveryId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'delivery_bids',
          callback: (p) async {
            final bid = Map<String, dynamic>.from(p.newRecord);
            if (bid['delivery_id'] != widget.deliveryId || !mounted) return;
            try {
              final enriched = await _db
                  .from('delivery_bids')
                  .select(
                      '*, '
                      'rider:riders(id, full_name, vehicle_type, rating_avg, phone), '
                      'company:companies(id, name, rating_avg, phone)')
                  .eq('id', bid['id'] as String)
                  .single();
              if (mounted) {
                setState(() {
                  if (!_bids.any((b) => b['id'] == bid['id'])) {
                    _bids.add(Map<String, dynamic>.from(enriched));
                    _bids.sort((a, b) =>
                        (a['amount'] as num).compareTo(b['amount'] as num));
                  }
                });
              }
            } catch (_) {}
          })
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'delivery_bids',
          callback: (p) {
            final bid = Map<String, dynamic>.from(p.newRecord);
            if (bid['delivery_id'] != widget.deliveryId || !mounted) return;
            setState(() {
              final idx = _bids.indexWhere((b) => b['id'] == bid['id']);
              if (idx != -1) _bids[idx] = {..._bids[idx], ...bid};
            });
          })
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'id',
            value:  widget.deliveryId,
          ),
          callback: (p) {
            final d = Map<String, dynamic>.from(p.newRecord);
            if (d['id'] != widget.deliveryId || !mounted) return;
            setState(() => _delivery = {...?_delivery, ...d});
          })
        .subscribe();
  }

  Future<void> _acceptBid(Map<String, dynamic> bid) async {
    setState(() => _accepting = true);
    try {
      final bidId   = bid['id']      as String;
      final delivId = widget.deliveryId;
      final amount  = bid['amount'];
      final riderId = bid['rider_id'] as String?;

      await _db.from('delivery_bids')
          .update({'status': 'accepted'}).eq('id', bidId);
      await _db.from('delivery_bids')
          .update({'status': 'rejected'})
          .eq('delivery_id', delivId).neq('id', bidId);
      await _db.from('deliveries').update({
        'agreed_price': amount,
        'status':       'assigned',
        'rider_id':     riderId,
        'assigned_at':  DateTime.now().toUtc().toIso8601String(),
      }).eq('id', delivId);

      _snack('Bid accepted! Your package is being arranged.');
      await _load();
    } catch (_) {
      _snack('Could not accept bid. Please try again.');
    }
    if (mounted) setState(() => _accepting = false);
  }

  Future<void> _confirmHandoff() async {
    setState(() => _confirming = true);
    try {
      await _db.from('deliveries')
          .update({'status': 'picked_up'}).eq('id', widget.deliveryId);
      _snack('Handoff confirmed! Rider is on the way.');
      await _load();
    } catch (_) {
      _snack('Could not confirm handoff. Please try again.');
    }
    if (mounted) setState(() => _confirming = false);
  }

  Future<void> _confirmReceipt() async {
    setState(() => _confirming = true);
    try {
      await _db.from('deliveries').update({
        'status':       'confirmed',
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.deliveryId);
      _snack('Receipt confirmed. Thank you!');
      await _load();
    } catch (_) {
      _snack('Could not confirm. Please try again.');
    }
    if (mounted) setState(() => _confirming = false);
  }

  void _snack(String msg) => Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      backgroundColor: EzizaColors.kPurple,
      colorText: EzizaColors.kWhite,
      snackPosition: SnackPosition.BOTTOM);

  // ────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: _loading
              ? _buildLoadingState()
              : _delivery == null
                  ? _buildNotFound()
                  : RefreshIndicator(
                      color: EzizaColors.kPurpleD,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                        children: [
                          if (widget.isRecipient) _recipientBanner(),
                          _statusStepper(),
                          _actionBanner(),
                          _routeCard(),
                          _packageCard(),
                          if (_showRiderCard()) _assignedRiderCard(),
                          if (_isTrackable()) ...[
                            _trackLiveButton(),
                            const SizedBox(height: 16),
                          ],
                          if (!widget.isRecipient) _bidsSection(),
                        ],
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildLoadingState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
              color: EzizaColors.kPurple.withValues(alpha: 0.1),
              blurRadius: 20)],
        ),
        child: const CircularProgressIndicator(
            color: EzizaColors.kPurpleD, strokeWidth: 2.5),
      ),
      const SizedBox(height: 16),
      const Text('Loading delivery…',
          style: TextStyle(color: EzizaColors.kMuted, fontSize: 13)),
    ]),
  );

  Widget _buildNotFound() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
            color: Color(0xFFF3E5F5), shape: BoxShape.circle),
        child: const Icon(Icons.search_off_rounded,
            size: 40, color: EzizaColors.kPurple),
      ),
      const SizedBox(height: 16),
      const Text('Delivery not found',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: EzizaColors.kText)),
      const SizedBox(height: 6),
      const Text('This delivery may have been removed.',
          style: TextStyle(color: EzizaColors.kMuted, fontSize: 13)),
    ]),
  );

  // ── Header ────────────────────────────────────────────────────

  Widget _buildHeader() {
    final status  = _delivery?['status'] as String? ?? 'open';
    final shortId = widget.deliveryId.length >= 8
        ? widget.deliveryId.substring(0, 8).toUpperCase()
        : widget.deliveryId.toUpperCase();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.only(
            bottomLeft:  Radius.circular(28),
            bottomRight: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: Color(0x556C3483), blurRadius: 16, offset: Offset(0, 6))
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(children: [
          Positioned(
            right: -24, top: 8,
            child: Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EzizaColors.kPurple.withValues(alpha: 0.12)),
            ),
          ),
          Positioned(
            left: -18, bottom: 10,
            child: Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EzizaColors.kGold.withValues(alpha: 0.07)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
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
                const SizedBox(width: 12),
                const Text('EZIZA',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white38,
                        letterSpacing: 2.5)),
                const Spacer(),
                if (!_loading) _statusChip(status),
              ]),
              const SizedBox(height: 14),
              const Text('Delivery Details',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5)),
              const SizedBox(height: 5),
              Row(children: [
                const Icon(Icons.tag_rounded, size: 11, color: Colors.white38),
                const SizedBox(width: 4),
                Text(shortId,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Container(width: 1, height: 10, color: Colors.white24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_statusSubtitle(status),
                      style: const TextStyle(fontSize: 12, color: Colors.white60),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Recipient identity banner ─────────────────────────────────

  Widget _recipientBanner() => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: EzizaColors.kTeal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: EzizaColors.kTeal.withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.move_to_inbox_rounded,
                color: EzizaColors.kTeal, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Incoming Delivery',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: EzizaColors.kText)),
                  SizedBox(height: 2),
                  Text('This package is addressed to you.',
                      style: TextStyle(
                          fontSize: 12,
                          color: EzizaColors.kMuted,
                          height: 1.3)),
                ],
              ),
            ),
          ]),
        ),
      );

  // ── Status stepper (vertical timeline) ───────────────────────

  Widget _statusStepper() {
    final status = _delivery?['status'] as String? ?? 'open';

    final steps = [
      ('open',                  'Request Placed',    'Your delivery is open for bids',          Icons.receipt_long_outlined),
      ('assigned',              'Rider Assigned',    'A rider is heading to the pickup point',   Icons.two_wheeler_rounded),
      ('awaiting_pickup_confirm','Rider at Pickup',  'Rider arrived — confirm the handoff',      Icons.handshake_outlined),
      ('picked_up',             'Package Collected', 'Your package is in transit',               Icons.local_shipping_outlined),
      ('delivered',             'Delivered',         'Package delivered — confirm receipt',       Icons.home_outlined),
      ('confirmed',             'Confirmed',         'Delivery complete. Thank you!',             Icons.verified_rounded),
    ];

    final statusOrder = steps.map((s) => s.$1).toList();
    final currentIdx  = statusOrder.indexOf(status).clamp(0, steps.length - 1);

    return _sectionCard(
      header: _sectionHeader(Icons.timeline_rounded, 'Delivery Progress'),
      child: Column(children: steps.asMap().entries.map((e) {
        final i       = e.key;
        final step    = e.value;
        final isDone  = i <= currentIdx;
        final isActive = i == currentIdx;
        final isLast  = i == steps.length - 1;

        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Left column: dot + connector line
            SizedBox(
              width: 44,
              child: Column(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: isDone
                        ? const LinearGradient(
                            colors: [EzizaColors.kPurple, EzizaColors.kPurpleD])
                        : null,
                    color: isDone ? null : EzizaColors.kBorder,
                    shape: BoxShape.circle,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                                color: EzizaColors.kPurpleD
                                    .withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 1)
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Icon(step.$4,
                        size: 16,
                        color: isDone ? Colors.white : EzizaColors.kMuted),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: i < currentIdx
                            ? const LinearGradient(
                                colors: [
                                  EzizaColors.kPurple,
                                  EzizaColors.kPurpleD
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter)
                            : null,
                        color: i < currentIdx ? null : EzizaColors.kBorder,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            // Right column: label + subtitle
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 7),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                      child: Text(step.$2,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isDone
                                  ? EzizaColors.kText
                                  : EzizaColors.kMuted)),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [
                                EzizaColors.kPurple,
                                EzizaColors.kPurpleD
                              ]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('NOW',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8)),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(step.$3,
                      style: TextStyle(
                          fontSize: 11,
                          color: isActive
                              ? EzizaColors.kPurpleD
                              : EzizaColors.kMuted,
                          height: 1.3)),
                ]),
              ),
            ),
          ]),
        );
      }).toList()),
    );
  }

  // ── Action banners ────────────────────────────────────────────

  Widget _actionBanner() {
    final status = _delivery?['status'] as String? ?? '';

    // Recipient does not manage pickup handoff
    if (widget.isRecipient && status == 'awaiting_pickup_confirm') {
      return const SizedBox.shrink();
    }

    if (status == 'awaiting_pickup_confirm') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: EzizaColors.kGold.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                  color: EzizaColors.kGold.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: EzizaColors.kGold.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: const Icon(Icons.two_wheeler_rounded,
                    color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Rider at Your Location',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF92400E))),
                  SizedBox(height: 3),
                  Text(
                      'Hand over the package to the rider, then confirm below.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92400E),
                          height: 1.3)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            _confirming
                ? const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: EzizaColors.kPurpleD)))
                : GestureDetector(
                    onTap: _confirmHandoff,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [
                              Color(0xFFD97706),
                              Color(0xFFB45309)
                            ]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFFD97706)
                                  .withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.handshake_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Confirm Handoff to Rider',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ]),
                    ),
                  ),
          ]),
        ),
      );
    }

    if (status == 'delivered') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF86EFAC)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                    color: Color(0xFFA7F3D0), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF16A34A), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Package Delivered!',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF15803D))),
                  SizedBox(height: 3),
                  Text(
                      'Your package has arrived. Please confirm receipt below.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF15803D),
                          height: 1.3)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            _confirming
                ? const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF16A34A))))
                : GestureDetector(
                    onTap: _confirmReceipt,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [
                              Color(0xFF16A34A),
                              Color(0xFF15803D)
                            ]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF16A34A)
                                  .withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.inventory_2_outlined,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Yes, I Received the Package',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ]),
                    ),
                  ),
          ]),
        ),
      );
    }

    if (status == 'confirmed') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(children: [
            Icon(Icons.verified_rounded,
                color: EzizaColors.kGold, size: 28),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Delivery Complete',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.white)),
                SizedBox(height: 2),
                Text('Thank you for using Eziza!',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
              ]),
            ),
          ]),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ── Route card ────────────────────────────────────────────────

  Widget _routeCard() {
    final d = _delivery!;
    return _sectionCard(
      header: _sectionHeader(Icons.route_rounded, 'Route'),
      child: Column(children: [
        _locationBox(
          label: 'PICKUP',
          address: d['pickup_address']       as String? ?? '',
          contactName:  d['pickup_contact_name']  as String?,
          contactPhone: d['pickup_contact_phone'] as String?,
          icon:  Icons.radio_button_checked_rounded,
          color: EzizaColors.kPurple,
        ),
        Row(children: [
          const SizedBox(width: 20),
          Container(
            width: 2,
            height: 26,
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [EzizaColors.kPurple, EzizaColors.kGold],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ]),
        _locationBox(
          label: 'DELIVERY',
          address: d['delivery_address']       as String? ?? '',
          contactName:  d['delivery_contact_name']  as String?,
          contactPhone: d['delivery_contact_phone'] as String?,
          icon:  Icons.location_on_rounded,
          color: EzizaColors.kGold,
        ),
      ]),
    );
  }

  Widget _locationBox({
    required String label,
    required String address,
    String? contactName,
    String? contactPhone,
    required IconData icon,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9,
                      color: color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(address,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: EzizaColors.kText,
                      height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (contactName != null || contactPhone != null) ...[
                const SizedBox(height: 5),
                Row(children: [
                  const Icon(Icons.person_outline_rounded,
                      size: 11, color: EzizaColors.kMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [contactName, contactPhone]
                          .whereType<String>()
                          .join('  ·  '),
                      style: const TextStyle(
                          fontSize: 11, color: EzizaColors.kMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
      );

  // ── Package card ──────────────────────────────────────────────

  Widget _packageCard() {
    final d     = _delivery!;
    final desc  = d['package_description'] as String? ?? '';
    final val   = (d['package_value'] as num?)?.toDouble();
    final price = (d['agreed_price'] as num?)?.toDouble();
    final state = d['pickup_state'] as String?;

    final hasDetails =
        desc.isNotEmpty || val != null || price != null || state != null;

    return _sectionCard(
      header: _sectionHeader(Icons.inventory_2_outlined, 'Package'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (desc.isNotEmpty) ...[
          Text(desc,
              style: const TextStyle(
                  fontSize: 13, color: EzizaColors.kText, height: 1.5)),
          const SizedBox(height: 12),
        ],
        if (val != null || price != null || state != null)
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (val != null)
              _infoPill('₦${val.toStringAsFixed(0)}',
                  Icons.inventory_outlined, EzizaColors.kNavy, label: 'Value'),
            if (price != null)
              _infoPill('₦${price.toStringAsFixed(0)}',
                  Icons.handshake_outlined, EzizaColors.kSuccess,
                  label: 'Agreed'),
            if (state != null && state.isNotEmpty)
              _infoPill(state, Icons.location_city_rounded,
                  EzizaColors.kPurple,
                  label: 'From'),
          ]),
        if (!hasDetails)
          const Text('No package details provided.',
              style: TextStyle(fontSize: 13, color: EzizaColors.kMuted)),
      ]),
    );
  }

  Widget _infoPill(String value, IconData icon, Color color,
      {String? label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
          if (label != null)
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ]),
      ]),
    );
  }

  // ── Assigned rider / company card ─────────────────────────────

  bool _showRiderCard() {
    final status  = _delivery?['status'] as String? ?? 'open';
    final riderId = _delivery?['rider_id'] as String?;
    if (status == 'open' || riderId == null) return false;
    final accepted =
        _bids.firstWhereOrNull((b) => b['status'] == 'accepted');
    return accepted != null &&
        (accepted['rider'] != null || accepted['company'] != null);
  }

  Widget _assignedRiderCard() {
    final accepted =
        _bids.firstWhereOrNull((b) => b['status'] == 'accepted');
    final rider   = accepted?['rider']   as Map<String, dynamic>?;
    final company = accepted?['company'] as Map<String, dynamic>?;
    if (rider == null && company == null) return const SizedBox.shrink();

    final isCompany = company != null && rider == null;
    final name   = isCompany
        ? (company['name']       as String? ?? '')
        : (rider!['full_name']   as String? ?? '');
    final sub    = isCompany
        ? 'Logistics Company'
        : (rider!['vehicle_type'] as String? ?? 'Rider');
    final rating = isCompany
        ? (company['rating_avg']  as num?)?.toDouble()
        : (rider?['rating_avg']   as num?)?.toDouble();

    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();

    return _sectionCard(
      header: _sectionHeader(
        isCompany ? Icons.business_rounded : Icons.two_wheeler_rounded,
        isCompany ? 'Logistics Company' : 'Your Rider',
      ),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(initials.isEmpty ? '?' : initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: EzizaColors.kText)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: EzizaColors.kPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(sub,
                    style: const TextStyle(
                        fontSize: 10,
                        color: EzizaColors.kPurpleD,
                        fontWeight: FontWeight.w700)),
              ),
              if (rating != null && rating > 0) ...[
                const SizedBox(width: 8),
                const Icon(Icons.star_rounded,
                    size: 13, color: EzizaColors.kGold),
                const SizedBox(width: 3),
                Text(rating.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 12,
                        color: EzizaColors.kText,
                        fontWeight: FontWeight.w700)),
              ],
            ]),
          ]),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: EzizaColors.kPurpleD.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.phone_rounded, size: 14, color: Colors.white),
            SizedBox(width: 5),
            Text('Call',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }

  // ── Track live button ─────────────────────────────────────────

  bool _isTrackable() {
    final status = _delivery?['status'] as String? ?? 'open';
    return [
      'assigned',
      'awaiting_pickup_confirm',
      'picked_up',
      'delivered'
    ].contains(status);
  }

  Widget _trackLiveButton() => GestureDetector(
    onTap: () =>
        Get.to(() => DeliveryTrackingPage(
              deliveryId: widget.deliveryId,
              isRecipient: widget.isRecipient,
            )),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: EzizaColors.kNavy,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: EzizaColors.kNavy.withValues(alpha: 0.45),
              blurRadius: 14,
              offset: const Offset(0, 5)),
          BoxShadow(
              color: EzizaColors.kPurple.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 2)),
        ],
      ),
      child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        Icon(Icons.location_on_rounded,
            color: EzizaColors.kGold, size: 20),
        SizedBox(width: 8),
        Text('Track Live on Map',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15)),
        SizedBox(width: 8),
        Icon(Icons.arrow_forward_ios_rounded,
            color: Colors.white38, size: 12),
      ]),
    ),
  );

  // ── Bids section ──────────────────────────────────────────────

  Widget _bidsSection() {
    final status      = _delivery?['status'] as String? ?? 'open';
    final isOpen      = status == 'open';
    final pendingBids = _bids.where((b) => b['status'] == 'pending').toList();
    final acceptedBid = _bids.firstWhereOrNull((b) => b['status'] == 'accepted');

    if (!isOpen && acceptedBid == null) return const SizedBox.shrink();

    return _sectionCard(
      header: _sectionHeader(
        isOpen ? Icons.gavel_rounded : Icons.check_circle_rounded,
        isOpen ? 'Bids Received' : 'Accepted Bid',
        badge: isOpen && pendingBids.isNotEmpty
            ? '${pendingBids.length}'
            : null,
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        if (isOpen && pendingBids.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: EzizaColors.kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EzizaColors.kBorder)),
            child: const Row(children: [
              Icon(Icons.hourglass_empty_rounded,
                  color: EzizaColors.kMuted, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'No bids yet. Riders and companies can bid for 24h.',
                    style: TextStyle(
                        fontSize: 12,
                        color: EzizaColors.kMuted,
                        height: 1.4)),
              ),
            ]),
          ),
        ],
        if (isOpen)
          ...pendingBids.asMap().entries.map(
              (e) => _bidCard(e.value, rank: e.key + 1, showAccept: true))
        else if (acceptedBid != null)
          _bidCard(acceptedBid, rank: 1, showAccept: false),
      ]),
    );
  }

  Widget _bidCard(Map<String, dynamic> bid,
      {required int rank, required bool showAccept}) {
    final amount     = (bid['amount'] as num?)?.toDouble() ?? 0;
    final riderId    = bid['rider_id']   as String?;
    final companyId  = bid['company_id'] as String?;
    final rider      = bid['rider']      as Map<String, dynamic>?;
    final company    = bid['company']    as Map<String, dynamic>?;

    final isCompanyBid = companyId != null && riderId == null;
    final name   = isCompanyBid
        ? (company?['name']        as String? ?? 'Company')
        : (rider?['full_name']     as String? ?? 'Rider');
    final sub    = isCompanyBid
        ? 'Company'
        : (rider?['vehicle_type'] as String? ?? 'Rider');
    final rating = isCompanyBid
        ? (company?['rating_avg'] as num?)?.toDouble()
        : (rider?['rating_avg']   as num?)?.toDouble();

    final initials = name
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();

    final isBest = rank == 1 && showAccept;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: isBest
            ? EzizaColors.kPurple.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isBest
                ? EzizaColors.kPurple.withValues(alpha: 0.25)
                : EzizaColors.kBorder),
        boxShadow: isBest
            ? [
                BoxShadow(
                    color: EzizaColors.kPurple.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]
            : null,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            // Avatar circle
            Stack(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: isBest
                      ? const LinearGradient(
                          colors: [
                            EzizaColors.kPurple,
                            EzizaColors.kPurpleD
                          ])
                      : null,
                  color: isBest ? null : EzizaColors.kBorder,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                      initials.isEmpty ? '$rank' : initials,
                      style: TextStyle(
                          color: isBest
                              ? Colors.white
                              : EzizaColors.kMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              if (isBest)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                        color: EzizaColors.kGold,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 1.5)),
                    child: const Icon(Icons.star_rounded,
                        size: 9, color: Colors.white),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: EzizaColors.kText)),
                  ),
                  if (isBest)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: EzizaColors.kGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Best Deal',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: EzizaColors.kGold)),
                    ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: EzizaColors.kSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: EzizaColors.kBorder),
                    ),
                    child: Text(sub,
                        style: const TextStyle(
                            fontSize: 10,
                            color: EzizaColors.kMuted,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (rating != null && rating > 0) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded,
                        size: 11, color: EzizaColors.kGold),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 11,
                            color: EzizaColors.kText,
                            fontWeight: FontWeight.w600)),
                  ],
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₦${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: EzizaColors.kText)),
              const Text('delivery fee',
                  style:
                      TextStyle(fontSize: 9, color: EzizaColors.kMuted)),
            ]),
          ]),
        ),
        if (showAccept) ...[
          Container(height: 1, color: EzizaColors.kBorder),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _accepting
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: EzizaColors.kPurpleD)))
                : GestureDetector(
                    onTap: () => _confirmAccept(bid),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [
                              EzizaColors.kPurple,
                              EzizaColors.kPurpleD
                            ]),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                              color: EzizaColors.kPurpleD
                                  .withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.check_rounded,
                            color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text('Accept This Bid',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ]),
                    ),
                  ),
          ),
        ],
      ]),
    );
  }

  void _confirmAccept(Map<String, dynamic> bid) {
    final amount = (bid['amount'] as num?)?.toDouble() ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.gavel_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Accept Bid?',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: EzizaColors.kText)),
            const SizedBox(height: 8),
            Text(
              'Accept this bid of ₦${amount.toStringAsFixed(0)}?\n'
              'All other bids will be declined.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: EzizaColors.kMuted, height: 1.5, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: EzizaColors.kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: EzizaColors.kBorder),
                    ),
                    child: const Center(
                        child: Text('Cancel',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: EzizaColors.kMuted))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _acceptBid(bid);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [
                            EzizaColors.kPurple,
                            EzizaColors.kPurpleD
                          ]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                        child: Text('Accept',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800))),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Layout helpers ────────────────────────────────────────────

  Widget _sectionCard(
          {required Widget header, required Widget child}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [
            BoxShadow(
                color: EzizaColors.kPurple.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: header,
          ),
          Container(
              height: 1,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              color: EzizaColors.kBorder),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ]),
      );

  Widget _sectionHeader(IconData icon, String title, {String? badge}) =>
      Row(children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 16, color: EzizaColors.kPurpleD),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: EzizaColors.kText)),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ]);

  Widget _statusChip(String status) {
    final (Color text, Color bg) = switch (status) {
      'open'                    => (EzizaColors.kPurpleD,    const Color(0xFFF3E5F5)),
      'assigned'                => (const Color(0xFF0284C7), const Color(0xFFE0F2FE)),
      'awaiting_pickup_confirm' => (const Color(0xFFD97706), const Color(0xFFFFF8E1)),
      'picked_up'               => (EzizaColors.kGold,       const Color(0xFFFFF8E1)),
      'delivered'               => (EzizaColors.kSuccess,    const Color(0xFFDCFCE7)),
      'confirmed'               => (EzizaColors.kSuccess,    const Color(0xFFDCFCE7)),
      _                         => (EzizaColors.kMuted,      const Color(0xFFF5F5F5)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(_statusLabel(status),
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: text)),
    );
  }

  String _statusLabel(String s) => switch (s) {
        'open'                    => 'Open',
        'assigned'                => 'Assigned',
        'awaiting_pickup_confirm' => 'Rider at Pickup',
        'picked_up'               => 'Picked Up',
        'delivered'               => 'Delivered',
        'confirmed'               => 'Confirmed',
        'cancelled'               => 'Cancelled',
        _                         => s,
      };

  String _statusSubtitle(String s) => switch (s) {
        'open'                    => 'Waiting for bids',
        'assigned'                => 'Rider heading to pickup',
        'awaiting_pickup_confirm' => 'Confirm handoff to rider',
        'picked_up'               => 'Package in transit',
        'delivered'               => 'Confirm receipt',
        'confirmed'               => 'Delivery complete',
        _                         => '',
      };
}
