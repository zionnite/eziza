import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import 'company_earnings_widgets.dart';
import 'company_map_page.dart';

class CompanyDashboardPage extends StatefulWidget {
  const CompanyDashboardPage({super.key});

  @override
  State<CompanyDashboardPage> createState() => _CompanyDashboardPageState();
}

class _CompanyDashboardPageState extends State<CompanyDashboardPage>
    with TickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _deliveriesTabController;
  late final TabController _earningsTabController;

  int _tab = 0;

  Map<String, dynamic>? _company;
  List<Map<String, dynamic>> _openDeliveries   = [];
  List<Map<String, dynamic>> _myBids           = [];
  List<Map<String, dynamic>> _activeDeliveries = [];
  List<Map<String, dynamic>> _jobHistory       = [];
  List<Map<String, dynamic>> _riders           = [];
  List<Map<String, dynamic>> _invites          = [];
  List<Map<String, dynamic>> _payoutHistory    = [];
  bool _loading = true;

  RealtimeChannel? _channel;

  final _phoneCtrl    = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _bidCtrl      = TextEditingController();
  final _payoutCtrl   = TextEditingController();
  bool _inviting      = false;
  bool _bidding       = false;
  bool _assigning     = false;
  bool _payoutLoading = false;

  @override
  void initState() {
    super.initState();
    _deliveriesTabController = TabController(length: 3, vsync: this);
    _earningsTabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    if (_channel != null) _db.removeChannel(_channel!);
    _deliveriesTabController.dispose();
    _earningsTabController.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _bidCtrl.dispose();
    _payoutCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────

  Future<void> _refreshCompanyBalance() async {
    final cid = _company?['id'] as String?;
    if (cid == null) return;
    try {
      final row = await _db
          .from('companies')
          .select('wallet_balance, total_earned, paid_out')
          .eq('id', cid)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() => _company = {..._company!, ...row});
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;

      final companyRes = await _db
          .from('companies')
          .select()
          .eq('auth_user_id', uid)
          .maybeSingle();
      _company = companyRes;
      if (_company == null) {
        setState(() => _loading = false);
        return;
      }

      final cid = _company!['id'] as String;

      final bidsRes = await _db
          .from('delivery_bids')
          .select()
          .eq('company_id', cid);
      _myBids = List<Map<String, dynamic>>.from(bidsRes);

      final pendingBidDeliveryIds = _myBids
          .where((b) => b['status'] == 'pending')
          .map((b) => b['delivery_id'] as String)
          .toSet();

      final acceptedBidDeliveryIds = _myBids
          .where((b) => b['status'] == 'accepted')
          .map((b) => b['delivery_id'] as String)
          .toList();

      if (acceptedBidDeliveryIds.isNotEmpty) {
        final activeRes = await _db
            .from('deliveries')
            .select()
            .inFilter('id', acceptedBidDeliveryIds)
            .inFilter('status', ['assigned', 'picked_up']);
        _activeDeliveries = List<Map<String, dynamic>>.from(activeRes);

        final historyRes = await _db
            .from('deliveries')
            .select()
            .inFilter('id', acceptedBidDeliveryIds)
            .inFilter('status', ['delivered', 'confirmed'])
            .order('created_at', ascending: false);
        _jobHistory = List<Map<String, dynamic>>.from(historyRes);
      } else {
        _activeDeliveries = [];
        _jobHistory = [];
      }

      final openRes = await _db
          .from('deliveries')
          .select()
          .eq('status', 'open')
          .order('created_at', ascending: false);
      _openDeliveries = List<Map<String, dynamic>>.from(openRes)
          .where((d) => !pendingBidDeliveryIds.contains(d['id'] as String))
          .toList();

      final acceptedInvites = await _db
          .from('company_rider_invites')
          .select('rider_id')
          .eq('company_id', cid)
          .eq('status', 'accepted');
      final riderAuthIds = (acceptedInvites as List)
          .map((i) => i['rider_id'] as String?)
          .whereType<String>()
          .toList();
      if (riderAuthIds.isNotEmpty) {
        final ridersRes = await _db
            .from('riders')
            .select()
            .inFilter('auth_user_id', riderAuthIds);
        _riders = List<Map<String, dynamic>>.from(ridersRes);
      } else {
        _riders = [];
      }

      final invitesRes = await _db
          .from('company_rider_invites')
          .select()
          .eq('company_id', cid)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      _invites = List<Map<String, dynamic>>.from(invitesRes);

      final payoutRes = await _db
          .from('company_payout_requests')
          .select()
          .eq('company_id', cid)
          .order('requested_at', ascending: false);
      _payoutHistory = List<Map<String, dynamic>>.from(payoutRes);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final cid = _company?['id'] as String?;
    if (cid == null) return;
    if (_channel != null) {
      _db.removeChannel(_channel!);
      _channel = null;
    }
    _channel = _db
        .channel('company_dashboard_${cid}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'deliveries',
          callback: (p) {
            final d = Map<String, dynamic>.from(p.newRecord);
            if (d['status'] == 'open' &&
                mounted &&
                !_openDeliveries.any((r) => r['id'] == d['id'])) {
              setState(() => _openDeliveries.insert(0, d));
            }
          })
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          callback: (p) {
            final d = Map<String, dynamic>.from(p.newRecord);
            if (!mounted) return;
            final status = d['status'] as String? ?? '';
            if (status != 'open') {
              setState(() =>
                  _openDeliveries.removeWhere((r) => r['id'] == d['id']));
            }
            final idx =
                _activeDeliveries.indexWhere((r) => r['id'] == d['id']);
            if (idx != -1) {
              if (status == 'delivered' || status == 'confirmed') {
                setState(() {
                  _activeDeliveries.removeAt(idx);
                  if (!_jobHistory.any((r) => r['id'] == d['id'])) {
                    _jobHistory.insert(0, d);
                  }
                });
                // Wallet balance was just credited by the earnings trigger —
                // refresh it so "Available Balance" isn't stale.
                if (status == 'confirmed') _refreshCompanyBalance();
              } else {
                setState(() => _activeDeliveries[idx] = d);
              }
            }
          })
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'delivery_bids',
          callback: (p) {
            final bid = Map<String, dynamic>.from(p.newRecord);
            if (bid['company_id'] != cid || !mounted) return;
            final idx = _myBids.indexWhere((b) => b['id'] == bid['id']);
            if (idx != -1) {
              setState(() => _myBids[idx] = bid);
            } else {
              setState(() => _myBids.add(bid));
            }
            if (bid['status'] == 'accepted') {
              _onBidAccepted(bid['delivery_id'] as String);
            }
          })
        .subscribe();
  }

  Future<void> _onBidAccepted(String deliveryId) async {
    try {
      final d = await _db
          .from('deliveries')
          .select()
          .eq('id', deliveryId)
          .single();
      if (!mounted) return;
      if (!_activeDeliveries.any((r) => r['id'] == deliveryId)) {
        setState(() {
          _openDeliveries.removeWhere((r) => r['id'] == deliveryId);
          _activeDeliveries.insert(0, Map<String, dynamic>.from(d));
        });
        Get.snackbar(
          'Bid Accepted! 🎉',
          'Your company won a delivery — assign it to a rider.',
          backgroundColor: EzizaColors.kSuccess,
          colorText: EzizaColors.kWhite,
          duration: const Duration(seconds: 5),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (_) {}
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _placeBid(String deliveryId, double amount) async {
    if (_company == null) return;
    setState(() => _bidding = true);
    try {
      await _db.from('delivery_bids').upsert({
        'delivery_id': deliveryId,
        'company_id':  _company!['id'],
        'amount':      amount,
        'status':      'pending',
      }, onConflict: 'delivery_id,company_id');
      _bidCtrl.clear();
      _snack('Bid of ₦${amount.toStringAsFixed(0)} submitted.');
      await _load();
    } catch (e) {
      _snack('Could not place bid: ${e.toString()}');
    }
    if (mounted) setState(() => _bidding = false);
  }

  Future<void> _assignRider(String deliveryId, String riderRowId) async {
    setState(() => _assigning = true);
    try {
      await _db
          .from('deliveries')
          .update({'rider_id': riderRowId, 'status': 'assigned'})
          .eq('id', deliveryId);

      final acceptedBid = _myBids.firstWhereOrNull(
          (b) => b['delivery_id'] == deliveryId && b['status'] == 'accepted');
      if (acceptedBid != null) {
        await _db
            .from('delivery_bids')
            .update({'rider_id': riderRowId})
            .eq('id', acceptedBid['id'] as String);
      }

      _snack('Rider assigned successfully.');
      await _load();
    } catch (_) {
      _snack('Could not assign rider. Try again.');
    }
    if (mounted) setState(() => _assigning = false);
  }

  Future<void> _inviteRider() async {
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (phone.isEmpty && email.isEmpty) {
      _snack('Enter a phone number or email address.');
      return;
    }
    if (_company == null) return;
    setState(() => _inviting = true);
    try {
      final cid = _company!['id'] as String;

      String? riderAuthId;
      if (phone.isNotEmpty) {
        final match = await _db
            .from('riders')
            .select('auth_user_id')
            .eq('phone', phone)
            .maybeSingle();
        riderAuthId = match?['auth_user_id'] as String?;
      }

      await _db.from('company_rider_invites').insert({
        'company_id':    cid,
        'rider_id':      riderAuthId,
        if (phone.isNotEmpty) 'invited_phone': phone,
        if (email.isNotEmpty) 'invited_email': email,
      });

      if (mounted) Navigator.of(context).pop();
      _phoneCtrl.clear();
      _emailCtrl.clear();
      _snack('Invite sent.');
      await _load();
    } catch (_) {
      _snack('Could not send invite. Please try again.');
    }
    if (mounted) setState(() => _inviting = false);
  }

  void _snack(String msg) => Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      backgroundColor: EzizaColors.kPurple,
      colorText: EzizaColors.kWhite,
      snackPosition: SnackPosition.BOTTOM);

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: IndexedStack(
        index: _tab,
        children: [
          _homeTab(),
          _deliveriesTab(),
          _ridersTab(),
          _earningsTab(),
          _accountTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() => Container(
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          boxShadow: [
            BoxShadow(
              color: EzizaColors.kPurple.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: EzizaColors.kPurpleD,
          unselectedItemColor: EzizaColors.kMuted,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.local_shipping_rounded), label: 'Deliveries'),
            BottomNavigationBarItem(
                icon: Icon(Icons.group_rounded), label: 'Riders'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Earnings'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded), label: 'Account'),
          ],
        ),
      );

  // ── HOME TAB ──────────────────────────────────────────────────

  Widget _homeTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: EzizaColors.kPurpleD));
    }
    if (_company == null) return _noCompany();

    final unassigned =
        _activeDeliveries.where((d) => d['rider_id'] == null).toList();

    return RefreshIndicator(
      color: EzizaColors.kPurpleD,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _companyHeaderWithStats()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 76, 20, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _companyDeliveryCta(),
                const SizedBox(height: 32),
                if (unassigned.isNotEmpty) ...[
                  _homeSectionLabel('Needs Rider Assignment',
                      Icons.assignment_late_rounded, EzizaColors.kError),
                  const SizedBox(height: 14),
                  ...unassigned.take(3).map(_activeCard),
                  if (unassigned.length > 3)
                    _homeViewAllBtn('${unassigned.length - 3} more',
                        () => setState(() => _tab = 1)),
                  const SizedBox(height: 32),
                ],
                _homeSectionLabel('Active Deliveries',
                    Icons.local_shipping_rounded, EzizaColors.kPurpleD),
                const SizedBox(height: 14),
                if (_activeDeliveries.isEmpty)
                  _homeEmptyDeliveries()
                else ...[
                  ..._activeDeliveries.take(3).map(_activeCard),
                  if (_activeDeliveries.length > 3)
                    _homeViewAllBtn(
                        '${_activeDeliveries.length - 3} more active',
                        () => setState(() => _tab = 1)),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyHeaderWithStats() {
    final completed = _jobHistory.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _companyHomeHdr(),
        Positioned(
          bottom: -52, left: 20, right: 20,
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            decoration: BoxDecoration(
              color: EzizaColors.kWhite,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF6C3483).withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Row(children: [
              _hfStat('${_activeDeliveries.length}', 'Active',
                  EzizaColors.kPurpleD),
              _hfDiv(),
              _hfStat('${_openDeliveries.length}', 'Available',
                  const Color(0xFF0284C7)),
              _hfDiv(),
              _hfStat('$completed', 'Completed', EzizaColors.kSuccess),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _companyHomeHdr() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft:  Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
                color: Color(0x556C3483),
                blurRadius: 18,
                offset: Offset(0, 6)),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -22, top: 6,
                child: Container(
                  width: 150, height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7E57C2).withValues(alpha: 0.13),
                  ),
                ),
              ),
              Positioned(
                left: -16, bottom: 10,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: EzizaColors.kGold.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EZIZA',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white38,
                            letterSpacing: 2.5)),
                    const SizedBox(height: 6),
                    Text(
                      _company?['name'] as String? ?? 'Company Dashboard',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_riders.length} rider${_riders.length == 1 ? '' : 's'} · ${_activeDeliveries.length + _jobHistory.length} deliveries',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _companyDeliveryCta() => GestureDetector(
        onTap: () => setState(() => _tab = 1),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: EzizaColors.kPurpleD.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5)),
            ],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _openDeliveries.isNotEmpty
                    ? Icons.local_shipping_rounded
                    : Icons.inbox_rounded,
                color: EzizaColors.kGold,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _openDeliveries.isNotEmpty
                        ? '${_openDeliveries.length} Deliveries Available'
                        : 'No Open Deliveries Yet',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _openDeliveries.isNotEmpty
                        ? 'Place bids to win new jobs'
                        : 'New requests will appear here',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white38, size: 14),
          ]),
        ),
      );

  Widget _homeSectionLabel(String title, IconData icon, Color color) =>
      Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: EzizaColors.kText,
                letterSpacing: 0.1)),
      ]);

  Widget _homeViewAllBtn(String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: EzizaColors.kPurpleD,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_rounded,
                size: 14, color: EzizaColors.kPurpleD),
          ]),
        ),
      );

  Widget _homeEmptyDeliveries() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            Icon(Icons.local_shipping_outlined,
                size: 40,
                color: EzizaColors.kMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            const Text('No active deliveries',
                style: TextStyle(fontSize: 13, color: EzizaColors.kMuted)),
          ]),
        ),
      );

  // ── Floating stats helpers ────────────────────────────────────

  Widget _hfStat(String value, String label, Color color) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1)),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: EzizaColors.kMuted,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _hfDiv() => Container(
        width: 1, height: 34,
        color: EzizaColors.kBorder,
        margin: const EdgeInsets.symmetric(horizontal: 4));

  // ── DELIVERIES TAB ────────────────────────────────────────────

  Widget _deliveriesTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: EzizaColors.kPurpleD));
    }
    if (_company == null) return _noCompany();

    final pendingBids =
        _myBids.where((b) => b['status'] == 'pending').toList();
    final inProgress = _activeDeliveries.length;
    final completed  = _jobHistory.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft:  Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                  color: Color(0x556C3483),
                  blurRadius: 16,
                  offset: Offset(0, 6)),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -20, top: 8,
                  child: Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF7E57C2).withValues(alpha: 0.13),
                    ),
                  ),
                ),
                Positioned(
                  left: -14, bottom: 30,
                  child: Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EzizaColors.kGold.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('EZIZA',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white38,
                                  letterSpacing: 2.5)),
                          const SizedBox(height: 6),
                          const Text('Deliveries',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3)),
                          const SizedBox(height: 3),
                          Text(
                            '${_activeDeliveries.length + _jobHistory.length} total · ${pendingBids.length} bid${pendingBids.length == 1 ? '' : 's'} pending',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white60),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Row(children: [
                              _jMiniStat('$inProgress', 'In Progress',
                                  Colors.white),
                              _jMiniStatDiv(),
                              _jMiniStat('${_openDeliveries.length}',
                                  'Available', EzizaColors.kGold),
                              _jMiniStatDiv(),
                              _jMiniStat('$completed', 'Completed',
                                  const Color(0xFF4ADE80)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TabBar(
                      controller: _deliveriesTabController,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      indicatorColor: EzizaColors.kGold,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.white.withValues(alpha: 0.15),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Active'),
                              if (_activeDeliveries.isNotEmpty ||
                                  pendingBids.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _jTabBadge(
                                    '${_activeDeliveries.length + pendingBids.length}',
                                    Colors.white,
                                    dark: true),
                              ],
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('History'),
                              if (_jobHistory.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _jTabBadge(
                                    '${_jobHistory.length}',
                                    Colors.white54),
                              ],
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Rating'),
                              if ((_company?['rating_count'] as num?) != null &&
                                  (_company!['rating_count'] as num) > 0) ...[
                                const SizedBox(width: 6),
                                _jTabBadge(
                                    '${_company!['rating_count']}',
                                    Colors.white54),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _deliveriesTabController,
            children: [
              // ── Active sub-tab ──
              RefreshIndicator(
                color: EzizaColors.kPurpleD,
                onRefresh: _load,
                child: _activeDeliveries.isEmpty &&
                        pendingBids.isEmpty &&
                        _openDeliveries.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: EzizaColors.kPurpleD
                                      .withValues(alpha: 0.07),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.local_shipping_outlined,
                                    size: 48,
                                    color: EzizaColors.kPurpleD
                                        .withValues(alpha: 0.45)),
                              ),
                              const SizedBox(height: 20),
                              const Text('No Active Deliveries',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: EzizaColors.kText),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              const Text(
                                  'Open delivery requests will appear here when available.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: EzizaColors.kMuted,
                                      fontSize: 13,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 60),
                        children: [
                          if (_activeDeliveries.isNotEmpty) ...[
                            _sectionLabel('Active Deliveries',
                                Icons.local_shipping_rounded,
                                EzizaColors.kGold),
                            const SizedBox(height: 10),
                            ..._activeDeliveries.map(_activeCard),
                            const SizedBox(height: 20),
                          ],
                          if (pendingBids.isNotEmpty) ...[
                            _sectionLabel('Your Pending Bids',
                                Icons.gavel_rounded, EzizaColors.kPurpleD),
                            const SizedBox(height: 10),
                            ...pendingBids.map(_pendingBidCard),
                            const SizedBox(height: 20),
                          ],
                          _sectionLabel(
                              'Available Deliveries (${_openDeliveries.length})',
                              Icons.inbox_rounded,
                              EzizaColors.kMuted),
                          const SizedBox(height: 10),
                          if (_openDeliveries.isEmpty)
                            _emptyCard(
                                'No open delivery requests right now'),
                          ..._openDeliveries.map(_openDeliveryCard),
                          const SizedBox(height: 20),
                        ],
                      ),
              ),
              // ── History sub-tab ──
              RefreshIndicator(
                color: EzizaColors.kPurpleD,
                onRefresh: _load,
                child: _jobHistory.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: EzizaColors.kPurpleD
                                      .withValues(alpha: 0.07),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.history_rounded,
                                    size: 48,
                                    color: EzizaColors.kPurpleD
                                        .withValues(alpha: 0.45)),
                              ),
                              const SizedBox(height: 20),
                              const Text('No Delivery History',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: EzizaColors.kText),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              const Text(
                                  'Completed deliveries will appear here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: EzizaColors.kMuted,
                                      fontSize: 13,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 60),
                        children: _jobHistory.map(_historyCard).toList(),
                      ),
              ),
              // ── Rating sub-tab ──
              RefreshIndicator(
                color: EzizaColors.kPurpleD,
                onRefresh: _load,
                child: _ratingSubTab(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ratingSubTab() {
    final avg   = (_company?['rating_avg'] as num?)?.toDouble() ?? 0.0;
    final count = (_company?['rating_count'] as num?)?.toInt() ?? 0;

    if (count == 0) {
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: EzizaColors.kPurpleD.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.star_outline_rounded,
                    size: 48,
                    color: EzizaColors.kPurpleD.withValues(alpha: 0.45)),
              ),
              const SizedBox(height: 20),
              const Text('No Ratings Yet',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: EzizaColors.kText),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                  'Ratings from customers will appear here once you complete deliveries.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: EzizaColors.kMuted,
                      fontSize: 13,
                      height: 1.4)),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EzizaColors.kBorder)),
        child: Column(children: [
          Text(avg.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: EzizaColors.kText)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < avg.round();
              return Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: EzizaColors.kGold,
                  size: 26);
            }),
          ),
          const SizedBox(height: 10),
          Text('Based on $count review${count == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 13, color: EzizaColors.kMuted)),
        ]),
      ),
    );
  }

  // ── Deliveries tab mini-stat helpers ──────────────────────────

  Widget _jMiniStat(String value, String label, Color color) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _jMiniStatDiv() => Container(
        width: 1, height: 24,
        color: Colors.white.withValues(alpha: 0.15),
        margin: const EdgeInsets.symmetric(horizontal: 2));

  Widget _jTabBadge(String count, Color color, {bool dark = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.2)
              : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(count,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );

  // ── RIDERS TAB ────────────────────────────────────────────────

  Widget _ridersTab() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft:  Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                    color: Color(0x556C3483),
                    blurRadius: 14,
                    offset: Offset(0, 5)),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EZIZA',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white38,
                            letterSpacing: 2.5)),
                    const SizedBox(height: 6),
                    const Text('My Riders',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 3),
                    Text(
                      '${_riders.length} rider${_riders.length == 1 ? '' : 's'} in your fleet',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: EzizaColors.kPurpleD,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GestureDetector(
                    onTap: _showAddRiderSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            EzizaColors.kPurple,
                            EzizaColors.kPurpleD
                          ]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                                color: EzizaColors.kPurpleD
                                    .withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ]),
                      child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.person_add_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Add Rider',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_riders.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          Get.to(() => CompanyMapPage(riders: _riders)),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                            color: EzizaColors.kNavy,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Icon(Icons.map_rounded,
                              color: EzizaColors.kGold, size: 16),
                          SizedBox(width: 6),
                          Text('Fleet Map',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (_riders.isNotEmpty) ...[
                    _sectionLabel(
                        'Your Riders (${_riders.length})',
                        Icons.group_rounded,
                        EzizaColors.kPurpleD),
                    const SizedBox(height: 10),
                    ..._riders.map(_riderCard),
                    const SizedBox(height: 20),
                  ],
                  if (_invites.isNotEmpty) ...[
                    _sectionLabel(
                        'Pending Invites (${_invites.length})',
                        Icons.mail_outline_rounded,
                        EzizaColors.kGold),
                    const SizedBox(height: 10),
                    ..._invites.map(_inviteCard),
                  ],
                  if (_riders.isEmpty && _invites.isEmpty)
                    _emptyCard(
                        'No riders yet. Add your first rider above.'),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      );

  // ── EARNINGS TAB ──────────────────────────────────────────────

  Widget _earningsTab() {
    if (_company == null) return _noCompany();
    final company      = _company!;
    final rawBalance   = (company['wallet_balance'] as num?)?.toDouble() ?? 0.0;
    final pendingPayout = _payoutHistory
        .where((p) => ['pending', 'approved'].contains(p['status']))
        .fold<double>(0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));
    final hasPending   = pendingPayout > 0;
    final balance      = (rawBalance - pendingPayout).clamp(0, double.infinity);
    final earningsHistory =
        _jobHistory.where((d) => d['status'] == 'confirmed').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft:  Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                  color: Color(0x556C3483),
                  blurRadius: 14,
                  offset: Offset(0, 5)),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('EZIZA',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white38,
                          letterSpacing: 2.5)),
                  const SizedBox(height: 6),
                  const Text('Earnings',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 3),
                  Text(
                    '₦${balance.toStringAsFixed(2)} available',
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color:
                          EzizaColors.kPurpleD.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Wallet Balance',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('₦${balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              if (hasPending) ...[
                const SizedBox(height: 2),
                Text(
                    '₦${pendingPayout.toStringAsFixed(2)} held for pending payout',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white54)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                _walletStat('Total Earned',
                    '₦${(company['total_earned'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                const SizedBox(width: 20),
                _walletStat('Paid Out',
                    '₦${(company['paid_out'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                const SizedBox(width: 20),
                _walletStat('Rating',
                    '${company['rating_avg'] ?? 0} ★'),
              ]),
              if (balance > 0 || hasPending) ...[
                const SizedBox(height: 14),
                hasPending
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 11),
                        decoration: BoxDecoration(
                            color: EzizaColors.kGold
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: EzizaColors.kGold
                                    .withValues(alpha: 0.5))),
                        child: const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                          Icon(Icons.hourglass_top_rounded,
                              color: EzizaColors.kGold, size: 15),
                          SizedBox(width: 7),
                          Text(
                              'Payment Requested — Awaiting Approval',
                              style: TextStyle(
                                  color: EzizaColors.kGold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                        ]),
                      )
                    : GestureDetector(
                        onTap: company['account_number'] != null
                            ? _showPayoutSheet
                            : () => _snack(
                                  'Add bank details during registration to request payouts.',
                                ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 11),
                          decoration: BoxDecoration(
                              color: Colors.white
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.2))),
                          child: const Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                            Icon(Icons.account_balance_rounded,
                                color: Colors.white, size: 15),
                            SizedBox(width: 7),
                            Text('Request Payout',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ]),
                        ),
                      ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 4),
        TabBar(
          controller: _earningsTabController,
          labelColor: EzizaColors.kPurpleD,
          unselectedLabelColor: EzizaColors.kMuted,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 13),
          indicatorColor: EzizaColors.kPurpleD,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: [
            Tab(text: 'Earnings (${earningsHistory.length})'),
            Tab(text: 'Payouts (${_payoutHistory.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _earningsTabController,
            children: [
              RefreshIndicator(
                color: EzizaColors.kPurpleD,
                onRefresh: _load,
                child: earningsHistory.isEmpty
                    ? _earningsEmptyState(
                        Icons.receipt_long_outlined,
                        'No Earnings Yet',
                        'Completed deliveries will show their earnings breakdown here.')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: earningsHistory.length,
                        itemBuilder: (_, i) =>
                            companyEarningsHistoryCard(earningsHistory[i]),
                      ),
              ),
              RefreshIndicator(
                color: EzizaColors.kPurpleD,
                onRefresh: _load,
                child: _payoutHistory.isEmpty
                    ? _earningsEmptyState(
                        Icons.account_balance_outlined,
                        'No Payout Requests',
                        'Requests you submit will show their status here.')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _payoutHistory.length,
                        itemBuilder: (_, i) =>
                            companyPayoutHistoryCard(_payoutHistory[i]),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _earningsEmptyState(IconData icon, String title, String subtitle) =>
      Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: EzizaColors.kPurpleD.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 48,
                    color: EzizaColors.kPurpleD.withValues(alpha: 0.45)),
              ),
              const SizedBox(height: 20),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: EzizaColors.kText),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: EzizaColors.kMuted,
                      fontSize: 13,
                      height: 1.4)),
            ],
          ),
        ),
      );

  // ── ACCOUNT TAB ───────────────────────────────────────────────

  Widget _accountTab() {
    final user     = _db.auth.currentUser;
    final email    = user?.email ?? '';
    final name     = _company?['name'] as String? ?? 'Company';
    final status   = _company?['status'] as String? ?? 'pending';
    final initials = name.trim().split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final balance =
        (_company?['wallet_balance'] as num?)?.toDouble() ?? 0.0;
    final completed = _jobHistory.length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _companyAccountHero(name, email, initials, status),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── STATS ───────────────────────────────────
                _acctSectionLabel('Stats'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 20, horizontal: 8),
                  decoration: BoxDecoration(
                    color: EzizaColors.kWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EzizaColors.kBorder),
                    boxShadow: [
                      BoxShadow(
                          color: EzizaColors.kPurple.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: Row(children: [
                    _acctStatCell('$completed', 'Deliveries',
                        EzizaColors.kPurpleD),
                    _acctVertDiv(),
                    _acctStatCell('${_riders.length}', 'Riders',
                        const Color(0xFF0284C7)),
                    _acctVertDiv(),
                    _acctStatCell(
                        '${_company?['rating_avg'] ?? 0}★',
                        'Rating',
                        EzizaColors.kSuccess),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── ACCOUNT ────────────────────────────────
                _acctSectionLabel('Account'),
                const SizedBox(height: 10),
                _acctCard(children: [
                  _acctTile(
                    icon: Icons.local_shipping_outlined,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Deliveries',
                    subtitle:
                        '${_activeDeliveries.length + _jobHistory.length} total',
                    onTap: () => setState(() => _tab = 1),
                  ),
                  _acctDivider(),
                  _acctTile(
                    icon: Icons.group_outlined,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'My Riders',
                    subtitle: '${_riders.length} in fleet',
                    onTap: () => setState(() => _tab = 2),
                  ),
                  _acctDivider(),
                  _acctTile(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Earnings',
                    subtitle: '₦${balance.toStringAsFixed(2)} balance',
                    onTap: () => setState(() => _tab = 3),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── SUPPORT ─────────────────────────────────
                _acctSectionLabel('Support'),
                const SizedBox(height: 10),
                _acctCard(children: [
                  _acctTile(
                    icon: Icons.support_agent_outlined,
                    iconColor: Colors.blueGrey,
                    iconBg: Colors.blueGrey.shade50,
                    title: 'Help & Support',
                    subtitle: 'Chat with us on WhatsApp',
                    onTap: () => Get.snackbar(
                      'Coming Soon',
                      'WhatsApp support will be available soon.',
                      snackPosition: SnackPosition.BOTTOM,
                    ),
                  ),
                  _acctDivider(),
                  _acctTile(
                    icon: Icons.alternate_email_rounded,
                    iconColor: Colors.blueGrey,
                    iconBg: Colors.blueGrey.shade50,
                    title: 'Email',
                    subtitle: email,
                    onTap: () {},
                    showTrailing: false,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── SIGN OUT ────────────────────────────────
                _acctCard(children: [
                  _acctTile(
                    icon: Icons.logout_rounded,
                    iconColor: EzizaColors.kError,
                    iconBg: EzizaColors.kError.withValues(alpha: 0.08),
                    title: 'Sign Out',
                    titleColor: EzizaColors.kError,
                    showTrailing: false,
                    onTap: _confirmSignOut,
                  ),
                ]),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyAccountHero(
      String name, String email, String initials, String status) =>
      Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft:  Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
                color: Color(0x446C3483),
                blurRadius: 16,
                offset: Offset(0, 6)),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -22, top: 10,
                child: Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: EzizaColors.kPurple.withValues(alpha: 0.13),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EZIZA',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white38,
                            letterSpacing: 2.5)),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(
                        width: 58, height: 58,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            EzizaColors.kPurple,
                            EzizaColors.kPurpleD,
                          ]),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: EzizaColors.kPurpleD
                                    .withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Center(
                          child: Text(initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3)),
                            const SizedBox(height: 4),
                            Text(email,
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusChipBg(status),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusChipLabel(status),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _statusChipColor(status)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Color _statusChipBg(String s) => switch (s) {
        'approved' => const Color(0xFF4ADE80).withValues(alpha: 0.2),
        'pending'  => EzizaColors.kGold.withValues(alpha: 0.2),
        _          => EzizaColors.kError.withValues(alpha: 0.2),
      };

  Color _statusChipColor(String s) => switch (s) {
        'approved' => const Color(0xFF4ADE80),
        'pending'  => EzizaColors.kGold,
        _          => EzizaColors.kError,
      };

  String _statusChipLabel(String s) => switch (s) {
        'approved' => 'Approved',
        'pending'  => 'Pending Review',
        _          => s,
      };

  // ── Account tab helpers ───────────────────────────────────────

  Widget _acctSectionLabel(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: EzizaColors.kMuted,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _acctCard({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [
            BoxShadow(
                color: EzizaColors.kPurple.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(children: children),
      );

  Widget _acctTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    String? subtitle,
    Color? titleColor,
    bool showTrailing = true,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: titleColor ?? EzizaColors.kText)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: EzizaColors.kMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (showTrailing)
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: EzizaColors.kMuted),
          ]),
        ),
      );

  Widget _acctDivider() => Divider(
      height: 1, indent: 70, endIndent: 16, color: Colors.grey.shade100);

  Widget _acctStatCell(String value, String label, Color color) =>
      Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1)),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: EzizaColors.kMuted,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _acctVertDiv() => Container(
        width: 1, height: 36,
        color: EzizaColors.kBorder,
        margin: const EdgeInsets.symmetric(horizontal: 4));

  void _confirmSignOut() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Icon(Icons.logout_rounded,
              color: EzizaColors.kError, size: 36),
          const SizedBox(height: 12),
          const Text('Sign Out',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: EzizaColors.kText)),
          const SizedBox(height: 8),
          const Text('Are you sure you want to sign out?',
              style: TextStyle(fontSize: 14, color: EzizaColors.kMuted)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Get.back(),
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
                            color: EzizaColors.kText)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Get.back();
                  Get.find<AuthController>().signOut();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: EzizaColors.kError,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('Sign Out',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── No company placeholder ────────────────────────────────────

  Widget _noCompany() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.business_outlined,
                size: 48, color: EzizaColors.kMuted),
            SizedBox(height: 12),
            Text('No approved company',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: EzizaColors.kText)),
            SizedBox(height: 6),
            Text('Your company application may still be under review.',
                style: TextStyle(fontSize: 12, color: EzizaColors.kMuted),
                textAlign: TextAlign.center),
          ]),
        ),
      );

  // ── Delivery cards ────────────────────────────────────────────

  Widget _activeCard(Map<String, dynamic> d) {
    final riderId       = d['rider_id'] as String?;
    final assignedRider = riderId != null
        ? _riders.firstWhereOrNull((r) => r['id'] == riderId)
        : null;
    final status  = d['status'] as String? ?? 'assigned';
    final delivId = d['id'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: EzizaColors.kGold.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
                color: EzizaColors.kGold.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: _routeLabel(
                  d['pickup_address'], d['delivery_address'])),
          const SizedBox(width: 8),
          _chip(_statusLabel(status), _statusText(status),
              _statusBg(status)),
        ]),
        const SizedBox(height: 10),
        if (assignedRider != null)
          Row(children: [
            const Icon(Icons.two_wheeler_rounded,
                size: 14, color: EzizaColors.kMuted),
            const SizedBox(width: 6),
            Text('Assigned: ${assignedRider['full_name'] ?? ''}',
                style: const TextStyle(
                    fontSize: 12, color: EzizaColors.kMuted)),
          ])
        else ...[
          const Text('No rider assigned yet',
              style: TextStyle(fontSize: 12, color: EzizaColors.kMuted)),
          const SizedBox(height: 8),
          if (_assigning)
            const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EzizaColors.kPurpleD)))
          else if (_riders.isEmpty)
            const Text('Add riders to your team first',
                style: TextStyle(
                    fontSize: 11,
                    color: EzizaColors.kMuted,
                    fontStyle: FontStyle.italic))
          else
            GestureDetector(
              onTap: () => _showAssignSheet(delivId),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: EzizaColors.kPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: EzizaColors.kPurpleD
                            .withValues(alpha: 0.3))),
                child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Icon(Icons.person_add_rounded,
                      size: 14, color: EzizaColors.kPurpleD),
                  SizedBox(width: 6),
                  Text('Assign a Rider',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: EzizaColors.kPurpleD)),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _pendingBidCard(Map<String, dynamic> bid) {
    final amount  = (bid['amount'] as num?)?.toDouble() ?? 0;
    final delivId = (bid['delivery_id'] as String? ?? '').substring(0, 8);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EzizaColors.kBorder)),
      child: Row(children: [
        const Icon(Icons.gavel_rounded,
            size: 16, color: EzizaColors.kPurpleD),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Delivery #$delivId…',
              style: const TextStyle(
                  fontSize: 13, color: EzizaColors.kText)),
        ),
        Text('₦${amount.toStringAsFixed(0)}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: EzizaColors.kText)),
        const SizedBox(width: 8),
        _chip('Pending', EzizaColors.kMuted, const Color(0xFFF5F5F5)),
      ]),
    );
  }

  Widget _openDeliveryCard(Map<String, dynamic> d) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EzizaColors.kBorder)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: _routeLabel(
                    d['pickup_address'], d['delivery_address'])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showBidSheet(d),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      EzizaColors.kPurple,
                      EzizaColors.kPurpleD
                    ]),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Place Bid',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          if (d['package_description'] != null) ...[
            const SizedBox(height: 6),
            Text(d['package_description'] as String,
                style: const TextStyle(
                    fontSize: 11, color: EzizaColors.kMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ]),
      );

  Widget _historyCard(Map<String, dynamic> d) {
    final price    = (d['agreed_price'] as num?)?.toDouble() ?? 0;
    final pickup   = d['pickup_address']   as String? ?? '';
    final delivery = d['delivery_address'] as String? ?? '';
    final date     = d['created_at'] as String? ?? '';
    final dateLabel =
        date.length >= 10 ? date.substring(0, 10) : date;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCFCE7))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded,
              size: 16, color: EzizaColors.kSuccess),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
                '${_shortAddr(pickup)} → ${_shortAddr(delivery)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EzizaColors.kText)),
            const SizedBox(height: 2),
            Text(dateLabel,
                style: const TextStyle(
                    fontSize: 11, color: EzizaColors.kMuted)),
          ]),
        ),
        if (price > 0)
          Text('₦${price.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: EzizaColors.kSuccess)),
      ]),
    );
  }

  Widget _riderCard(Map<String, dynamic> rider) {
    final isAvailable = rider['is_available'] as bool? ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EzizaColors.kBorder)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
              shape: BoxShape.circle),
          child: const Icon(Icons.two_wheeler_rounded,
              color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(rider['full_name'] as String? ?? '',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: EzizaColors.kText)),
            Text(rider['vehicle_type'] as String? ?? '',
                style: const TextStyle(
                    fontSize: 12, color: EzizaColors.kMuted)),
          ]),
        ),
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: isAvailable
                    ? EzizaColors.kSuccess
                    : EzizaColors.kMuted,
                shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          isAvailable ? 'Online' : 'Offline',
          style: TextStyle(
              fontSize: 11,
              color: isAvailable
                  ? EzizaColors.kSuccess
                  : EzizaColors.kMuted,
              fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  Widget _inviteCard(Map<String, dynamic> invite) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: EzizaColors.kGold.withValues(alpha: 0.3))),
        child: Row(children: [
          const Icon(Icons.mail_outline_rounded,
              color: EzizaColors.kGold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (invite['invited_phone'] != null)
                Text(invite['invited_phone'] as String,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: EzizaColors.kText)),
              if (invite['invited_email'] != null)
                Text(invite['invited_email'] as String,
                    style: const TextStyle(
                        fontSize: 12, color: EzizaColors.kMuted)),
            ]),
          ),
          _chip('Pending', EzizaColors.kGold, const Color(0xFFFFF8E1)),
        ]),
      );

  // ── Bottom sheets ─────────────────────────────────────────────

  void _showPayoutSheet() {
    final pendingPayout = _payoutHistory
        .where((p) => ['pending', 'approved'].contains(p['status']))
        .fold<double>(0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));
    final balance =
        (((_company?['wallet_balance'] as num?)?.toDouble() ?? 0.0) - pendingPayout)
            .clamp(0, double.infinity);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Request Payout',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: EzizaColors.kText)),
            const SizedBox(height: 4),
            Text('Available: ₦${balance.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 13, color: EzizaColors.kMuted)),
            const SizedBox(height: 20),
            _inputField(
                _payoutCtrl,
                'Amount to withdraw (₦)',
                Icons.payments_outlined,
                const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 20),
            _payoutLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: EzizaColors.kPurpleD))
                : _gradientBtn('Request Payout', () async {
                    final amt =
                        double.tryParse(_payoutCtrl.text.trim());
                    if (amt == null || amt <= 0) {
                      _snack('Enter a valid amount.');
                      return;
                    }
                    if (amt > balance) {
                      _snack(
                          'Only ₦${balance.toStringAsFixed(2)} available.');
                      return;
                    }
                    Navigator.of(ctx).pop();
                    ss(() => _payoutLoading = true);
                    try {
                      await _db
                          .from('company_payout_requests')
                          .insert({
                        'company_id': _company!['id'],
                        'amount':     amt,
                      });
                      _payoutCtrl.clear();
                      _snack('Payout request submitted.');
                      await _load();
                    } catch (_) {
                      _snack('Payout failed. Try again.');
                    }
                    if (mounted) setState(() => _payoutLoading = false);
                  }),
          ]),
        );
      }),
    );
  }

  void _showAddRiderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Add Rider to Your Team',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: EzizaColors.kText)),
            const SizedBox(height: 4),
            const Text("Enter the rider's phone number and/or email.",
                style: TextStyle(fontSize: 12, color: EzizaColors.kMuted)),
            const SizedBox(height: 20),
            _inputField(_phoneCtrl, 'Phone Number',
                Icons.phone_rounded, TextInputType.phone),
            const SizedBox(height: 12),
            _inputField(_emailCtrl, 'Email Address',
                Icons.email_outlined, TextInputType.emailAddress),
            const SizedBox(height: 20),
            _inviting
                ? const Center(
                    child: CircularProgressIndicator(
                        color: EzizaColors.kPurpleD))
                : _gradientBtn('Send Invite', () async {
                    ss(() {});
                    await _inviteRider();
                    if (mounted) ss(() {});
                  }),
          ]),
        );
      }),
    );
  }

  void _showBidSheet(Map<String, dynamic> d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _routeLabel(d['pickup_address'], d['delivery_address']),
            const SizedBox(height: 16),
            _inputField(
                _bidCtrl,
                'Your delivery fee (₦)',
                Icons.payments_outlined,
                const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 14),
            _bidding
                ? const Center(
                    child: CircularProgressIndicator(
                        color: EzizaColors.kPurpleD))
                : _gradientBtn('Submit Bid', () {
                    final amt =
                        double.tryParse(_bidCtrl.text.trim());
                    if (amt == null || amt <= 0) {
                      _snack('Enter a valid amount.');
                      return;
                    }
                    Navigator.of(ctx).pop();
                    _placeBid(d['id'] as String, amt);
                  }),
          ]),
        );
      }),
    );
  }

  void _showAssignSheet(String deliveryId) {
    String? selectedRiderRowId;
    final available =
        _riders.where((r) => r['status'] == 'approved').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Assign a Rider',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: EzizaColors.kText)),
            const SizedBox(height: 16),
            if (available.isEmpty)
              const Text(
                  'No approved riders available. Ensure your riders are approved.',
                  style: TextStyle(
                      fontSize: 13, color: EzizaColors.kMuted)),
            ...available.map((rider) => GestureDetector(
                  onTap: () => ss(
                      () => selectedRiderRowId = rider['id'] as String),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: selectedRiderRowId == rider['id']
                            ? EzizaColors.kPurple
                                .withValues(alpha: 0.08)
                            : EzizaColors.kSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: selectedRiderRowId == rider['id']
                                ? EzizaColors.kPurpleD
                                : EzizaColors.kBorder)),
                    child: Row(children: [
                      Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [
                                EzizaColors.kPurple,
                                EzizaColors.kPurpleD
                              ]),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.two_wheeler_rounded,
                              color: Colors.white, size: 14)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            rider['full_name'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: EzizaColors.kText)),
                      ),
                      if (selectedRiderRowId == rider['id'])
                        const Icon(Icons.check_circle_rounded,
                            color: EzizaColors.kPurpleD, size: 20),
                    ]),
                  ),
                )),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: selectedRiderRowId == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      _assignRider(deliveryId, selectedRiderRowId!);
                    },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                    gradient: selectedRiderRowId != null
                        ? const LinearGradient(colors: [
                            EzizaColors.kPurple,
                            EzizaColors.kPurpleD
                          ])
                        : null,
                    color: selectedRiderRowId == null
                        ? EzizaColors.kBorder
                        : null,
                    borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text('Confirm Assignment',
                      style: TextStyle(
                          color: selectedRiderRowId != null
                              ? Colors.white
                              : EzizaColors.kMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────

  Widget _sectionLabel(String label, IconData icon, Color color) =>
      Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: color)),
      ]);

  Widget _routeLabel(dynamic from, dynamic to) => Row(children: [
        const Icon(Icons.radio_button_unchecked,
            size: 13, color: EzizaColors.kPurpleD),
        const SizedBox(width: 4),
        Flexible(
          child: Text(_shortAddr(from?.toString() ?? '—'),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: EzizaColors.kText),
              overflow: TextOverflow.ellipsis),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Icon(Icons.arrow_forward_rounded,
              size: 13, color: EzizaColors.kMuted),
        ),
        const Icon(Icons.location_on_rounded,
            size: 13, color: EzizaColors.kGold),
        const SizedBox(width: 4),
        Flexible(
          child: Text(_shortAddr(to?.toString() ?? '—'),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: EzizaColors.kText),
              overflow: TextOverflow.ellipsis),
        ),
      ]);

  Widget _chip(String label, Color text, Color bg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: text)),
      );

  Widget _emptyCard(String msg) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EzizaColors.kBorder)),
        child: Center(
            child: Text(msg,
                style: const TextStyle(
                    fontSize: 13, color: EzizaColors.kMuted),
                textAlign: TextAlign.center)),
      );

  Widget _inputField(TextEditingController ctrl, String hint,
          IconData icon, TextInputType type) =>
      Container(
        decoration: BoxDecoration(
            color: EzizaColors.kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: EzizaColors.kBorder)),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          style:
              const TextStyle(fontSize: 14, color: EzizaColors.kText),
          inputFormatters: type == TextInputType.number ||
                  type ==
                      const TextInputType.numberWithOptions(decimal: true)
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
              : null,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: EzizaColors.kMuted),
            hintText: hint,
            hintStyle: const TextStyle(
                color: EzizaColors.kMuted, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
                vertical: 14, horizontal: 12),
          ),
        ),
      );

  Widget _gradientBtn(String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ]),
          child: Center(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15))),
        ),
      );

  Widget _walletStat(String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ]);

  // ── Status helpers ────────────────────────────────────────────

  String _shortAddr(String addr) {
    if (addr.isEmpty) return '—';
    final parts = addr.split(',');
    return parts.first.trim().length > 22
        ? '${parts.first.trim().substring(0, 22)}…'
        : parts.first.trim();
  }

  String _statusLabel(String s) => switch (s) {
        'assigned'  => 'Assigned',
        'picked_up' => 'Picked Up',
        'delivered' => 'Delivered',
        _           => s,
      };

  Color _statusText(String s) => switch (s) {
        'assigned'  => const Color(0xFF0284C7),
        'picked_up' => EzizaColors.kGold,
        'delivered' => EzizaColors.kSuccess,
        _           => EzizaColors.kMuted,
      };

  Color _statusBg(String s) => switch (s) {
        'assigned'  => const Color(0xFFE0F2FE),
        'picked_up' => const Color(0xFFFFF8E1),
        'delivered' => const Color(0xFFDCFCE7),
        _           => const Color(0xFFF5F5F5),
      };
}
