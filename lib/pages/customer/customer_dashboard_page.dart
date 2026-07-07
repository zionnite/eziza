import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import 'customer_delivery_detail_page.dart';
import 'delivery_tracking_page.dart';
import 'send_package_page.dart';

class CustomerDashboardPage extends StatefulWidget {
  const CustomerDashboardPage({super.key});

  @override
  State<CustomerDashboardPage> createState() => _CustomerDashboardPageState();
}

class _CustomerDashboardPageState extends State<CustomerDashboardPage>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _active   = [];
  List<Map<String, dynamic>> _history  = [];
  List<Map<String, dynamic>> _incoming = [];
  bool _loading = true;
  int  _tab     = 0;
  late final TabController _deliveryTabController;
  RealtimeChannel? _channel;

  static const _activeStatuses = [
    'open', 'assigned', 'awaiting_pickup_confirm', 'picked_up', 'delivered'
  ];
  static const _historyStatuses = ['confirmed', 'cancelled'];

  String get _name =>
      (_db.auth.currentUser?.userMetadata?['full_name'] as String?)
          ?.split(' ')
          .first ??
      'there';

  @override
  void initState() {
    super.initState();
    _deliveryTabController = TabController(length: 3, vsync: this);
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _deliveryTabController.dispose();
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await Future.wait([_loadSent(), _loadIncoming()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSent() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      final res = await _db
          .from('deliveries')
          .select()
          .eq('customer_id', uid)
          .order('created_at', ascending: false);
      final all = List<Map<String, dynamic>>.from(res);
      if (mounted) {
        setState(() {
          _active  = all.where((d) => _activeStatuses.contains(d['status'])).toList();
          _history = all.where((d) => _historyStatuses.contains(d['status'])).toList();
        });
      }
    } catch (e) {
      debugPrint('[CustomerDash] _loadSent error: $e');
    }
  }

  Future<void> _loadIncoming() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      // RLS "recipient_can_read_delivery" policy filters by phone match.
      // Exclude deliveries I also created to avoid showing them in both tabs.
      final res = await _db
          .from('deliveries')
          .select()
          .neq('customer_id', uid)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _incoming = List<Map<String, dynamic>>.from(res));
      }
    } catch (e) {
      debugPrint('[CustomerDash] _loadIncoming error: $e');
    }
  }

  void _subscribeRealtime() {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    if (_channel != null) { _db.removeChannel(_channel!); _channel = null; }
    _channel = _db
        .channel('cust_dash_${uid}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          // No column filter — RLS sends events for both sent and incoming deliveries.
          callback: (p) {
            if (!mounted) return;
            _refreshQuiet();
          },
        )
        .subscribe();
  }

  Future<void> _refreshQuiet() async {
    await Future.wait([_loadSent(), _loadIncoming()]);
  }

  Future<void> _openDetail(String id) async {
    await Get.to(() => CustomerDeliveryDetailPage(deliveryId: id));
    await _load();
  }

  Future<void> _openIncomingDetail(String id) async {
    await Get.to(() => CustomerDeliveryDetailPage(deliveryId: id, isRecipient: true));
    await _load();
  }

  Future<void> _sendPackage() async {
    await Get.to(() => const SendPackagePage());
    _load();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: IndexedStack(
        index: _tab,
        children: [
          _homeTab(),
          _deliveriesTab(),
          _accountTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _tab == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fab_track',
                  onPressed: _showFindPackageSheet,
                  backgroundColor: EzizaColors.kTeal,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Find Package',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'fab_send',
                  onPressed: _sendPackage,
                  backgroundColor: EzizaColors.kPurple,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Send Package',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            )
          : null,
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
    return RefreshIndicator(
      color: EzizaColors.kPurpleD,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _headerWithStats()),
          SliverPadding(
            // 76 = 52px card overhang + 24px gap so nothing overlaps
            // 160 = extra bottom so content clears the two stacked FABs
            padding: const EdgeInsets.fromLTRB(20, 76, 20, 160),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(children: [
                  Expanded(child: _quickSendCta()),
                  const SizedBox(width: 12),
                  Expanded(child: _quickTrackCta()),
                ]),
                const SizedBox(height: 32),
                _sectionLabel('Active Deliveries',
                    Icons.local_shipping_rounded, EzizaColors.kPurpleD),
                const SizedBox(height: 14),
                if (_active.isEmpty)
                  _bigEmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No active deliveries',
                    subtitle: 'Tap "Send Package" below to get started.',
                  )
                else ...[
                  ..._active.take(3).map(_deliveryCard),
                  if (_active.length > 3)
                    _viewAllBtn(
                        '${_active.length - 3} more active',
                        () => setState(() => _tab = 1)),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── DELIVERIES TAB ────────────────────────────────────────────

  Widget _deliveriesTab() {
    final inTransit = _active.where((d) => [
          'assigned', 'awaiting_pickup_confirm', 'picked_up', 'delivered'
        ].contains(d['status'])).length;
    final completed = _history.where((d) => d['status'] == 'confirmed').length;
    final toConfirm = _incoming.where((d) => d['status'] == 'delivered').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header block — dark gradient matching other screens ──
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
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
                // Glow circles
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
                          const Text(
                            'My Deliveries',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${_active.length + _history.length} sent · ${_incoming.length} incoming',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white60),
                          ),
                          const SizedBox(height: 16),

                          // ── Stats row (frosted glass card) ──────────
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Row(children: [
                              _miniStat('${_active.length + _history.length}',
                                  'Sent', Colors.white),
                              _miniStatDiv(),
                              _miniStat('$inTransit', 'In Transit',
                                  EzizaColors.kGold),
                              _miniStatDiv(),
                              _miniStat('$completed', 'Done',
                                  const Color(0xFF4ADE80)),
                              _miniStatDiv(),
                              _miniStat('${_incoming.length}', 'Incoming',
                                  EzizaColors.kTeal),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Tabs ────────────────────────────────────
                    TabBar(
                      controller: _deliveryTabController,
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
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Active'),
                              if (_active.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _tabBadge(
                                    '${_active.length}', Colors.white, dark: true),
                              ],
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('History'),
                              if (_history.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _tabBadge(
                                    '${_history.length}', Colors.white54),
                              ],
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Incoming'),
                              if (toConfirm > 0) ...[
                                const SizedBox(width: 6),
                                _tabBadge('$toConfirm', EzizaColors.kGold,
                                    dark: true),
                              ] else if (_incoming.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _tabBadge('${_incoming.length}', Colors.white54),
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

        // ── Tab views ──────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: EzizaColors.kPurpleD))
              : TabBarView(
                  controller: _deliveryTabController,
                  children: [
                    RefreshIndicator(
                      color: EzizaColors.kPurpleD,
                      onRefresh: _load,
                      child: _active.isEmpty
                          ? _bigEmptyState(
                              icon: Icons.local_shipping_outlined,
                              title: 'No active deliveries',
                              subtitle:
                                  'Send a package and track it in real time right here.',
                              ctaLabel: 'Send a Package',
                              onCta: _sendPackage,
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 60),
                              children: _active.map(_deliveryCard).toList(),
                            ),
                    ),
                    RefreshIndicator(
                      color: EzizaColors.kPurpleD,
                      onRefresh: _load,
                      child: _history.isEmpty
                          ? _bigEmptyState(
                              icon: Icons.history_rounded,
                              title: 'No delivery history',
                              subtitle:
                                  'Completed and cancelled deliveries will appear here.',
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 60),
                              children: _history.map(_deliveryCard).toList(),
                            ),
                    ),
                    RefreshIndicator(
                      color: EzizaColors.kPurpleD,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
                        children: [
                          _findPackageBanner(),
                          const SizedBox(height: 16),
                          if (_incoming.isEmpty)
                            _bigEmptyState(
                              icon: Icons.move_to_inbox_rounded,
                              title: 'No incoming deliveries',
                              subtitle:
                                  'Deliveries matched by phone or claimed by ID appear here.',
                            )
                          else
                            ..._incoming.map(_incomingDeliveryCard),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Mini stat (analytics bar) ─────────────────────────────────

  Widget _miniStat(String value, String label, Color color) => Expanded(
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

  Widget _miniStatDiv() => Container(
        width: 1, height: 24,
        color: Colors.white.withValues(alpha: 0.15),
        margin: const EdgeInsets.symmetric(horizontal: 2));

  Widget _tabBadge(String count, Color color, {bool dark = false}) =>
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
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color)),
      );

  // ── ACCOUNT TAB ───────────────────────────────────────────────

  Widget _accountTab() {
    final user     = _db.auth.currentUser;
    final email    = user?.email ?? '';
    final full     = (user?.userMetadata?['full_name'] as String?) ?? _name;
    final phone    = (user?.userMetadata?['phone'] as String?) ?? '';
    final initials = full.trim().split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _accountHero(full, email, initials),
          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── ACCOUNT ────────────────────────────────
                _settingsSectionLabel('Account'),
                const SizedBox(height: 10),
                _settingsCard(children: [
                  _settingsTile(
                    icon: Icons.local_shipping_outlined,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'My Deliveries',
                    subtitle: '${_active.length + _history.length} orders total',
                    onTap: () => setState(() => _tab = 1),
                  ),
                  _tileDivider(),
                  _settingsTile(
                    icon: Icons.person_outline_rounded,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Edit Profile',
                    subtitle: full,
                    onTap: () => _showEditProfileSheet(full, phone),
                  ),
                  _tileDivider(),
                  _settingsTile(
                    icon: Icons.lock_outline_rounded,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Change Password',
                    onTap: () => _showChangePasswordSheet(),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── STATS ───────────────────────────────────
                _settingsSectionLabel('Stats'),
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
                    _acctStat(
                        '${_active.length + _history.length}',
                        'All Orders',
                        EzizaColors.kPurpleD),
                    _vertDiv(),
                    _acctStat('${_active.length}', 'Active',
                        const Color(0xFF0284C7)),
                    _vertDiv(),
                    _acctStat(
                        '${_history.where((d) => d['status'] == 'confirmed').length}',
                        'Completed',
                        EzizaColors.kSuccess),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── SUPPORT ─────────────────────────────────
                _settingsSectionLabel('Support'),
                const SizedBox(height: 10),
                _settingsCard(children: [
                  _settingsTile(
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
                  _tileDivider(),
                  _settingsTile(
                    icon: phone.isNotEmpty
                        ? Icons.fingerprint_rounded
                        : Icons.alternate_email_rounded,
                    iconColor: Colors.blueGrey,
                    iconBg: Colors.blueGrey.shade50,
                    title: phone.isNotEmpty ? 'Phone' : 'Email',
                    subtitle: phone.isNotEmpty ? phone : email,
                    onTap: () {},
                    showTrailing: false,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── LOGOUT ──────────────────────────────────
                _settingsCard(children: [
                  _settingsTile(
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

  // ── Account hero header ───────────────────────────────────────

  Widget _accountHero(String full, String email, String initials) =>
      Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
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
                    Row(children: [
                      const Text('EZIZA',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.white38,
                              letterSpacing: 2.5)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Online',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
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
                            Text(full,
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

  // ── Settings helpers ──────────────────────────────────────────

  Widget _settingsSectionLabel(String title) => Padding(
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

  Widget _settingsCard({required List<Widget> children}) => Container(
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

  Widget _settingsTile({
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
                  color: iconBg, borderRadius: BorderRadius.circular(10)),
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

  Widget _tileDivider() =>
      Divider(height: 1, indent: 70, endIndent: 16, color: Colors.grey.shade100);

  // ── Sign-out sheet ────────────────────────────────────────────

  void _confirmSignOut() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24), topRight: Radius.circular(24)),
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

  // ── Edit profile sheet ────────────────────────────────────────

  void _showEditProfileSheet(String currentName, String currentPhone) {
    final nameCtrl  = TextEditingController(text: currentName);
    final phoneCtrl = TextEditingController(text: currentPhone);
    bool saving = false;

    Get.bottomSheet(
      StatefulBuilder(builder: (ctx, setS) {
        return Container(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Edit Profile',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: EzizaColors.kText)),
              ),
              const SizedBox(height: 20),
              _inputField(nameCtrl, 'Full Name', Icons.person_outline_rounded),
              const SizedBox(height: 14),
              _inputField(phoneCtrl, 'Phone Number', Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: saving
                    ? null
                    : () async {
                        setS(() => saving = true);
                        try {
                          await _db.auth.updateUser(UserAttributes(
                            data: {
                              'full_name': nameCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                            },
                          ));
                          Get.back();
                          if (mounted) setState(() {});
                          Get.snackbar('Done', 'Profile updated.',
                              snackPosition: SnackPosition.BOTTOM);
                        } catch (_) {
                          Get.snackbar('Error', 'Could not update profile.',
                              snackPosition: SnackPosition.BOTTOM);
                        } finally {
                          setS(() => saving = false);
                        }
                      },
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
                    ],
                  ),
                  child: Center(
                    child: saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Save Changes',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
      isScrollControlled: true,
    );
  }

  // ── Change password sheet ─────────────────────────────────────

  void _showChangePasswordSheet() {
    final ctrl = TextEditingController();
    bool saving  = false;
    bool visible = false;

    Get.bottomSheet(
      StatefulBuilder(builder: (ctx, setS) {
        return Container(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Change Password',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: EzizaColors.kText)),
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Enter your new password below.',
                  style: TextStyle(fontSize: 13, color: EzizaColors.kMuted)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              obscureText: !visible,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'New password',
                hintStyle:
                    const TextStyle(color: EzizaColors.kMuted, fontSize: 14),
                filled: true,
                fillColor: EzizaColors.kSurface,
                prefixIcon: const Icon(Icons.lock_outline,
                    color: EzizaColors.kPurple, size: 20),
                suffixIcon: GestureDetector(
                  onTap: () => setS(() => visible = !visible),
                  child: Icon(
                    visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: EzizaColors.kMuted, size: 20,
                  ),
                ),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EzizaColors.kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EzizaColors.kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: EzizaColors.kPurple, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: saving
                  ? null
                  : () async {
                      if (ctrl.text.trim().length < 6) {
                        Get.snackbar('Too short',
                            'Password must be at least 6 characters.',
                            snackPosition: SnackPosition.BOTTOM);
                        return;
                      }
                      setS(() => saving = true);
                      try {
                        await _db.auth.updateUser(
                            UserAttributes(password: ctrl.text.trim()));
                        Get.back();
                        Get.snackbar('Done', 'Password updated.',
                            snackPosition: SnackPosition.BOTTOM);
                      } catch (_) {
                        Get.snackbar('Error', 'Could not update password.',
                            snackPosition: SnackPosition.BOTTOM);
                      } finally {
                        setS(() => saving = false);
                      }
                    },
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
                  ],
                ),
                child: Center(
                  child: saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Update Password',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                ),
              ),
            ),
          ]),
        );
      }),
      isScrollControlled: true,
    );
  }

  Widget _inputField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: EzizaColors.kMuted, fontSize: 14),
          filled: true,
          fillColor: EzizaColors.kSurface,
          prefixIcon: Icon(icon, color: EzizaColors.kPurple, size: 20),
          contentPadding: const EdgeInsets.all(14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: EzizaColors.kPurple, width: 1.5),
          ),
        ),
      );

  // ── Stat widgets ──────────────────────────────────────────────

  Widget _acctStat(String value, String label, Color color) => Expanded(
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

  Widget _vertDiv() => Container(
        width: 1, height: 36,
        color: EzizaColors.kBorder,
        margin: const EdgeInsets.symmetric(horizontal: 4));

  // ── Header + floating stats card ─────────────────────────────

  Widget _headerWithStats() {
    final open = _active.where((d) => d['status'] == 'open').length;
    final inTransit = _active.where((d) => [
          'assigned', 'awaiting_pickup_confirm', 'picked_up', 'delivered'
        ].contains(d['status'])).length;
    final done       = _history.where((d) => d['status'] == 'confirmed').length;
    final toConfirm  = _incoming.where((d) => d['status'] == 'delivered').length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _header(_name),
        Positioned(
          bottom: -52, left: 20, right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
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
              _floatStat('$open', 'Awaiting\nBid', EzizaColors.kPurpleD),
              _floatDiv(),
              _floatStat('$inTransit', 'In\nTransit', const Color(0xFF0284C7)),
              _floatDiv(),
              _floatStat('$done', 'Completed', EzizaColors.kSuccess),
              if (toConfirm > 0) ...[
                _floatDiv(),
                _floatStat('$toConfirm', 'Confirm\nReceipt', EzizaColors.kGold),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _floatStat(String value, String label, Color color) => Expanded(
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
                  fontWeight: FontWeight.w600,
                  height: 1.3),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _floatDiv() => Container(
        width: 1, height: 34,
        color: EzizaColors.kBorder,
        margin: const EdgeInsets.symmetric(horizontal: 4));

  // ── Quick-send CTA ────────────────────────────────────────────

  Widget _quickSendCta() => GestureDetector(
        onTap: _sendPackage,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_box_rounded,
                    color: EzizaColors.kGold, size: 22),
              ),
              const SizedBox(height: 14),
              const Text('Send a\nPackage',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
              const SizedBox(height: 4),
              const Text('Fast & reliable',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      );

  Widget _quickTrackCta() => GestureDetector(
        onTap: _showFindPackageSheet,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF007A8A), Color(0xFF005F6E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: EzizaColors.kTeal.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.search_rounded,
                    color: EzizaColors.kGold, size: 22),
              ),
              const SizedBox(height: 14),
              const Text('Track a\nPackage',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
              const SizedBox(height: 4),
              const Text('Enter tracking code',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      );

  Widget _viewAllBtn(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      color: EzizaColors.kPurpleD,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded,
                  size: 14, color: EzizaColors.kPurpleD),
            ],
          ),
        ),
      );

  // ── Header (home) ─────────────────────────────────────────────

  Widget _header(String name) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('EZIZA',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white38,
                                  letterSpacing: 2.5)),
                          const SizedBox(height: 4),
                          Text('Hello, $name! 👋',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3)),
                          const SizedBox(height: 3),
                          const Text('Track your packages and send new ones.',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.white60)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _confirmSignOut,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: const Icon(Icons.logout_rounded,
                            size: 18, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  // ── Section label ─────────────────────────────────────────────

  Widget _sectionLabel(String title, IconData icon, Color color) => Row(
        children: [
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
        ],
      );

  // ── Delivery card ─────────────────────────────────────────────

  Widget _deliveryCard(Map<String, dynamic> d) {
    final status    = d['status']           as String? ?? 'open';
    final pickup    = d['pickup_address']   as String? ?? '';
    final dropoff   = d['delivery_address'] as String? ?? '';
    final price     = (d['agreed_price']    as num?)?.toDouble();
    final createdAt = DateTime.tryParse(d['created_at'] as String? ?? '');
    final id        = d['id'] as String;
    final isTrackable = [
      'assigned', 'awaiting_pickup_confirm', 'picked_up', 'delivered'
    ].contains(status);

    final (Color statusColor, _, IconData statusIcon) = _statusMeta(status);

    // Contextual banner (custom_fit pattern — only for actionable states)
    final String? bannerMsg = switch (status) {
      'open'                    => 'Waiting for rider bids',
      'awaiting_pickup_confirm' => 'Rider arrived — confirm handoff to start delivery',
      'delivered'               => 'Package delivered — confirm receipt to complete',
      _                         => null,
    };

    return GestureDetector(
      onTap: () => _openDetail(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [
            BoxShadow(
              color: EzizaColors.kPurple.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left colored accent bar (referral pattern)
                Container(width: 4, color: statusColor),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Banner for actionable states (custom_fit pattern)
                      if (bannerMsg != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          color: statusColor.withValues(alpha: 0.07),
                          child: Row(children: [
                            Icon(Icons.info_outline_rounded,
                                size: 12, color: statusColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(bannerMsg,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: statusColor,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                        ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            // Top row: icon + route summary + status chip
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Status icon container (referral/_EarningRow pattern)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(statusIcon,
                                      size: 18, color: statusColor),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_shortAddr(pickup),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: EzizaColors.kText),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 3),
                                      Row(children: [
                                        Icon(Icons.arrow_downward_rounded,
                                            size: 10,
                                            color: EzizaColors.kMuted
                                                .withValues(alpha: 0.6)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(_shortAddr(dropoff),
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: EzizaColors.kMuted),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _statusChip(status),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Info pills row (custom_fit _pill pattern)
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              if (createdAt != null)
                                _infoPill(Icons.schedule_outlined,
                                    _fmtDate(createdAt)),
                              if (price != null)
                                _infoPill(Icons.payments_outlined,
                                    '₦${_fmtNum(price)}',
                                    highlight: true),
                            ]),
                          ],
                        ),
                      ),

                      // Footer: view details link + track button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Row(children: [
                          const Row(children: [
                            Text('View Details',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: EzizaColors.kPurpleD)),
                            SizedBox(width: 3),
                            Icon(Icons.arrow_forward_rounded,
                                size: 12, color: EzizaColors.kPurpleD),
                          ]),
                          const Spacer(),
                          if (isTrackable)
                            GestureDetector(
                              onTap: () => Get.to(
                                  () => DeliveryTrackingPage(deliveryId: id)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    EzizaColors.kPurple,
                                    EzizaColors.kPurpleD,
                                  ]),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: EzizaColors.kPurpleD
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3))
                                  ],
                                ),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on_rounded,
                                          size: 12, color: EzizaColors.kGold),
                                      SizedBox(width: 5),
                                      Text('Track Live',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ]),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Find package by ID ───────────────────────────────────────

  Widget _findPackageBanner() => GestureDetector(
        onTap: _showFindPackageSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: EzizaColors.kTeal.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: EzizaColors.kTeal.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EzizaColors.kTeal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.search_rounded,
                  color: EzizaColors.kTeal, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Find Package by ID',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: EzizaColors.kText)),
                  SizedBox(height: 2),
                  Text('Enter the ID the sender shared with you',
                      style: TextStyle(
                          fontSize: 11, color: EzizaColors.kMuted)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: EzizaColors.kMuted),
          ]),
        ),
      );

  void _showFindPackageSheet() {
    final codeCtrl = TextEditingController();
    bool loading = false;
    Map<String, dynamic>? result;
    String? error;

    Get.bottomSheet(
      StatefulBuilder(builder: (ctx, setS) {
        Future<void> doFind() async {
          final code = codeCtrl.text.trim().toUpperCase();
          if (code.isEmpty) return;
          setS(() { loading = true; result = null; error = null; });
          try {
            final res = await _db.rpc(
              'find_and_claim_delivery',
              params: {'p_code': code},
            );
            final data = Map<String, dynamic>.from(res as Map);
            if (data['error'] != null) {
              setS(() { error = data['error'] as String; loading = false; });
            } else {
              // Refresh incoming list in background (don't await — sheet stays open)
              _loadIncoming();
              setS(() { result = data; loading = false; });
            }
          } catch (e) {
            setS(() {
              error = 'Could not look up delivery. Please try again.';
              loading = false;
            });
          }
        }

        return Container(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          decoration: const BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.only(
              topLeft:  Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),

                // Header
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: EzizaColors.kTeal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded,
                        color: EzizaColors.kTeal, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Track My Package',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: EzizaColors.kText)),
                        Text('Enter the 6-character code from the sender',
                            style: TextStyle(
                                fontSize: 12, color: EzizaColors.kMuted)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // Code input + search button
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: codeCtrl,
                      style: const TextStyle(
                          fontSize: 20,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w800),
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      onSubmitted: (_) => doFind(),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'A B C 1 2 3',
                        hintStyle: TextStyle(
                            color: EzizaColors.kMuted.withValues(alpha: 0.4),
                            fontSize: 20,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w400),
                        filled: true,
                        fillColor: EzizaColors.kSurface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: EzizaColors.kBorder)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: EzizaColors.kBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: EzizaColors.kPurple, width: 1.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: loading ? null : doFind,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          EzizaColors.kPurple,
                          EzizaColors.kPurpleD,
                        ]),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3)),
                        ],
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.search_rounded,
                              color: Colors.white, size: 22),
                    ),
                  ),
                ]),

                // Error
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: EzizaColors.kError.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: EzizaColors.kError.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded,
                          color: EzizaColors.kError, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(error!,
                            style: const TextStyle(
                                color: EzizaColors.kError, fontSize: 12,
                                height: 1.3)),
                      ),
                    ]),
                  ),
                ],

                // Success card — package found & auto-claimed
                if (result != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: EzizaColors.kSuccess.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: EzizaColors.kSuccess.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Found banner
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color:
                                  EzizaColors.kSuccess.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: EzizaColors.kSuccess, size: 16),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Package Found!',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: EzizaColors.kText)),
                                Text('Added to your Incoming tab.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: EzizaColors.kMuted)),
                              ],
                            ),
                          ),
                          // Tracking code badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: EzizaColors.kPurpleD.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              result!['tracking_code'] as String? ?? '',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: EzizaColors.kPurpleD,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        // Status + route
                        Row(children: [
                          _statusChip(result!['status'] as String? ?? 'open',
                              isRecipient: true),
                        ]),
                        const SizedBox(height: 12),
                        _previewRoute(
                          pickup:  result!['pickup_address']   as String? ?? '',
                          dropoff: result!['delivery_address'] as String? ?? '',
                        ),
                        if (result!['agreed_price'] != null) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            const Icon(Icons.payments_outlined,
                                size: 13, color: EzizaColors.kMuted),
                            const SizedBox(width: 5),
                            Text(
                              '₦${_fmtNum((result!['agreed_price'] as num).toDouble())}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: EzizaColors.kPurpleD,
                                  fontWeight: FontWeight.w700),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 16),
                        // View delivery button
                        GestureDetector(
                          onTap: () {
                            Get.back();
                            setState(() => _tab = 1);
                            _deliveryTabController.animateTo(2);
                            Get.to(() => CustomerDeliveryDetailPage(
                                  deliveryId:  result!['delivery_id'] as String,
                                  isRecipient: true,
                                ));
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                EzizaColors.kPurple,
                                EzizaColors.kPurpleD,
                              ]),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                    color: EzizaColors.kPurpleD
                                        .withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4)),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.local_shipping_rounded,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text('View & Track Delivery',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
      isScrollControlled: true,
    );
  }

  Widget _previewRoute({required String pickup, required String dropoff}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.radio_button_checked_rounded,
                size: 12, color: EzizaColors.kPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _shortAddr(pickup),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EzizaColors.kText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Container(
              width: 2, height: 16,
              color: EzizaColors.kBorder,
              margin: const EdgeInsets.symmetric(vertical: 3),
            ),
          ),
          Row(children: [
            const Icon(Icons.location_on_rounded,
                size: 12, color: EzizaColors.kGold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _shortAddr(dropoff),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EzizaColors.kText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      );

  // ── Incoming delivery card ────────────────────────────────────

  Widget _incomingDeliveryCard(Map<String, dynamic> d) {
    final status   = d['status']           as String? ?? 'open';
    final pickup   = d['pickup_address']   as String? ?? '';
    final dropoff  = d['delivery_address'] as String? ?? '';
    final price    = (d['agreed_price']    as num?)?.toDouble();
    final createdAt = DateTime.tryParse(d['created_at'] as String? ?? '');
    final id       = d['id'] as String;
    final needsConfirm  = status == 'delivered';
    final isTrackable = ['assigned', 'awaiting_pickup_confirm', 'picked_up', 'delivered']
        .contains(status);

    final (Color statusColor, _, IconData statusIcon) = _statusMeta(status);

    return GestureDetector(
      onTap: () => _openIncomingDetail(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: needsConfirm
                ? EzizaColors.kGold.withValues(alpha: 0.5)
                : EzizaColors.kBorder,
            width: needsConfirm ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (needsConfirm ? EzizaColors.kGold : EzizaColors.kPurple)
                  .withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: statusColor),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "Incoming" label banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        color: needsConfirm
                            ? EzizaColors.kGold.withValues(alpha: 0.08)
                            : EzizaColors.kTeal.withValues(alpha: 0.07),
                        child: Row(children: [
                          Icon(
                            needsConfirm
                                ? Icons.check_circle_outline_rounded
                                : Icons.move_to_inbox_rounded,
                            size: 12,
                            color: needsConfirm
                                ? EzizaColors.kGold
                                : EzizaColors.kTeal,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            needsConfirm
                                ? 'Package delivered — tap to confirm receipt'
                                : 'Incoming delivery addressed to you',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: needsConfirm
                                  ? EzizaColors.kGold
                                  : EzizaColors.kTeal,
                            ),
                          ),
                        ]),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child:
                                      Icon(statusIcon, size: 18, color: statusColor),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_shortAddr(pickup),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: EzizaColors.kText),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 3),
                                      Row(children: [
                                        Icon(Icons.arrow_downward_rounded,
                                            size: 10,
                                            color: EzizaColors.kMuted
                                                .withValues(alpha: 0.6)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(_shortAddr(dropoff),
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: EzizaColors.kMuted),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _statusChip(status, isRecipient: true),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              if (createdAt != null)
                                _infoPill(Icons.schedule_outlined,
                                    _fmtDate(createdAt)),
                              if (price != null)
                                _infoPill(Icons.payments_outlined,
                                    '₦${_fmtNum(price)}',
                                    highlight: true),
                            ]),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        child: Row(children: [
                          const Row(children: [
                            Text('View Details',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: EzizaColors.kPurpleD)),
                            SizedBox(width: 3),
                            Icon(Icons.arrow_forward_rounded,
                                size: 12, color: EzizaColors.kPurpleD),
                          ]),
                          const Spacer(),
                          if (isTrackable && !needsConfirm)
                            GestureDetector(
                              onTap: () => Get.to(() => DeliveryTrackingPage(
                                    deliveryId: id,
                                    isRecipient: true,
                                  )),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    EzizaColors.kPurple,
                                    EzizaColors.kPurpleD,
                                  ]),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: EzizaColors.kPurpleD
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3))
                                  ],
                                ),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on_rounded,
                                          size: 12, color: EzizaColors.kGold),
                                      SizedBox(width: 5),
                                      Text('Track Live',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ]),
                              ),
                            ),
                          if (needsConfirm)
                            GestureDetector(
                              onTap: () => _openIncomingDetail(id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    EzizaColors.kGold,
                                    Color(0xFFD97706),
                                  ]),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: EzizaColors.kGold
                                            .withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3))
                                  ],
                                ),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded,
                                          size: 12, color: Colors.white),
                                      SizedBox(width: 5),
                                      Text('Confirm Receipt',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                    ]),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Status metadata ───────────────────────────────────────────

  (Color, Color, IconData) _statusMeta(String status) => switch (status) {
        'open' => (
            EzizaColors.kPurpleD,
            const Color(0xFFF3E5F5),
            Icons.gavel_rounded,
          ),
        'assigned' => (
            const Color(0xFF0284C7),
            const Color(0xFFE0F2FE),
            Icons.person_pin_circle_rounded,
          ),
        'awaiting_pickup_confirm' => (
            const Color(0xFFD97706),
            const Color(0xFFFFF8E1),
            Icons.where_to_vote_rounded,
          ),
        'picked_up' => (
            EzizaColors.kGold,
            const Color(0xFFFFF8E1),
            Icons.local_shipping_rounded,
          ),
        'delivered' => (
            EzizaColors.kSuccess,
            const Color(0xFFDCFCE7),
            Icons.check_circle_outline_rounded,
          ),
        'confirmed' => (
            EzizaColors.kSuccess,
            const Color(0xFFDCFCE7),
            Icons.verified_rounded,
          ),
        'cancelled' => (
            EzizaColors.kError,
            const Color(0xFFFFEBEE),
            Icons.cancel_outlined,
          ),
        _ => (
            EzizaColors.kMuted,
            const Color(0xFFF5F5F5),
            Icons.help_outline_rounded,
          ),
      };

  // ── Info pill (custom_fit _pill pattern) ──────────────────────

  Widget _infoPill(IconData icon, String label, {bool highlight = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: highlight
              ? EzizaColors.kPurpleD.withValues(alpha: 0.08)
              : const Color(0xFFF3E5F5),
          borderRadius: BorderRadius.circular(20),
          border: highlight
              ? Border.all(
                  color: EzizaColors.kPurpleD.withValues(alpha: 0.2))
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: EzizaColors.kPurpleD),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: EzizaColors.kPurpleD)),
        ]),
      );

  // ── Big empty state (custom_fit pattern) ──────────────────────

  Widget _bigEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? ctaLabel,
    VoidCallback? onCta,
  }) =>
      Center(
        child: SingleChildScrollView(
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
              if (ctaLabel != null && onCta != null) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: onCta,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        EzizaColors.kPurple,
                        EzizaColors.kPurpleD,
                      ]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color:
                                EzizaColors.kPurpleD.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(ctaLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  // ── Number formatter (comma-separated) ───────────────────────

  String _fmtNum(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  Widget _statusChip(String status, {bool isRecipient = false}) {
    final (Color text, Color bg) = switch (status) {
      'open'                    => (EzizaColors.kPurpleD,    const Color(0xFFF3E5F5)),
      'assigned'                => (const Color(0xFF0284C7), const Color(0xFFE0F2FE)),
      'awaiting_pickup_confirm' => (const Color(0xFFD97706), const Color(0xFFFFF8E1)),
      'picked_up'               => (EzizaColors.kGold,       const Color(0xFFFFF8E1)),
      'delivered'               => (EzizaColors.kSuccess,    const Color(0xFFDCFCE7)),
      'confirmed'               => (EzizaColors.kSuccess,    const Color(0xFFDCFCE7)),
      'cancelled'               => (EzizaColors.kError,      const Color(0xFFFFEBEE)),
      _                         => (EzizaColors.kMuted,      const Color(0xFFF5F5F5)),
    };
    final label = switch (status) {
      'open'                    => 'Awaiting Bids',
      'assigned'                => 'Rider Assigned',
      'awaiting_pickup_confirm' => isRecipient ? 'Awaiting Handoff' : 'Confirm Handoff',
      'picked_up'               => 'In Transit',
      'delivered'               => 'Delivered',
      'confirmed'               => 'Completed',
      'cancelled'               => 'Cancelled',
      _                         => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${dt.day} ${months[dt.month]}';
    }
  }
}
