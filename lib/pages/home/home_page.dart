import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../services/supabase_service.dart';
import 'company_dashboard_page.dart';
import 'company_registration_page.dart';
import 'rider_application_page.dart';

class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key});

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  final _db = Supabase.instance.client;
  bool _hasCompany      = false;
  bool _companyApproved = false;

  @override
  void initState() {
    super.initState();
    _checkCompany();
  }

  Future<void> _checkCompany() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final row = await _db
        .from('companies')
        .select('status')
        .eq('auth_user_id', uid)
        .maybeSingle();
    if (mounted && row != null) {
      setState(() {
        _hasCompany      = true;
        _companyApproved = row['status'] == 'approved';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final user = _db.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] as String?)?.split(' ').first
        ?? 'there';

    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero header ──────────────────────────────────
          _buildHero(name, auth),
          // ── Action cards ─────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // ── Become a Rider ─────────────────────────────
              _ActionCard(
                icon: Icons.two_wheeler_rounded,
                iconColor: EzizaColors.kPurple,
                iconBg: EzizaColors.kPurple.withValues(alpha: 0.1),
                title: 'Become a Rider',
                subtitle:
                    'Apply to deliver packages and earn money on your schedule.',
                onTap: () => Get.to(() => const RiderApplicationPage()),
              ),
              const SizedBox(height: 16),

              // ── Register Company ────────────────────────────
              _ActionCard(
                icon: Icons.business_rounded,
                iconColor: EzizaColors.kNavy,
                iconBg: EzizaColors.kNavy.withValues(alpha: 0.08),
                title: _hasCompany ? 'Company Dashboard' : 'Register a Company',
                subtitle: _hasCompany
                    ? 'Manage deliveries and your rider fleet.'
                    : 'Set up your logistics company and manage a fleet of riders.',
                badge: _hasCompany && !_companyApproved ? 'Pending' : null,
                onTap: _hasCompany
                    ? () => Get.to(() => const CompanyDashboardPage())
                    : () => Get.to(() => const CompanyRegistrationPage()),
              ),
              const SizedBox(height: 16),

              // ── Customer / Send & Receive ────────────────────
              _ActionCard(
                icon: Icons.local_shipping_rounded,
                iconColor: EzizaColors.kGold,
                iconBg: EzizaColors.kGold.withValues(alpha: 0.1),
                title: 'Send & Receive Packages',
                subtitle:
                    'Use Eziza to send packages, get real-time tracking, and confirm delivery.',
                onTap: () async {
                  await SupabaseService.setCustomerRole();
                  // Setting isCustomer triggers _AuthRouter to rebuild → CustomerDashboardPage
                  Get.find<AuthController>().isCustomer.value = true;
                },
              ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(String name, AuthController auth) {
    return Container(
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
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -24, top: 8,
              child: Container(
                width: 160, height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EzizaColors.kPurple.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              left: -18, bottom: 20,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EzizaColors.kGold.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'EZIZA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white38,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => auth.signOut(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: const Icon(Icons.logout_rounded,
                              size: 16, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hello, $name! 👋',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'How would you like to use Eziza?',
                    style: TextStyle(
                        color: Colors.white60, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [
            BoxShadow(
              color: EzizaColors.kPurple.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: EzizaColors.kText)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: EzizaColors.kGold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(badge!,
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: EzizaColors.kGold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: EzizaColors.kMuted,
                          fontSize: 13,
                          height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: EzizaColors.kMuted, size: 22),
          ],
        ),
      ),
    );
  }
}
