import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../constants/colors.dart';

/// End-User License Agreement, shown/linked from the signup page (Apple App
/// Store review expects this for account-creating apps). Structurally
/// ported from ZeeFashion's policy.dart EULA sections, adapted for Eziza's
/// logistics context (delivery/package handling, wallet & payouts, and the
/// 3-role rider/company/customer model instead of a single buyer/seller
/// marketplace).
class EulaPage extends StatelessWidget {
  const EulaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Column(children: [
        _hero(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _mainCard(),
              const SizedBox(height: 18),
              _section(
                title: 'License Grant',
                icon: Icons.workspace_premium_outlined,
                content:
                    'Eziza grants you a personal, non-transferable and non-exclusive license to use the Eziza application on devices under your control.',
              ),
              _section(
                title: 'Restrictions',
                icon: Icons.gpp_bad_outlined,
                content:
                    'You may not modify, reverse engineer, reproduce, distribute, resell or use the software in violation of any applicable law or platform policy.',
              ),
              _section(
                title: 'Delivery & Package Handling',
                icon: Icons.local_shipping_outlined,
                content:
                    'Riders and logistics companies on Eziza are independent providers of delivery services, not employees or agents of Eziza. Eziza facilitates the connection between senders, riders, and companies but does not itself transport packages. Senders are responsible for accurately describing package contents and value, and for not shipping prohibited, illegal, or hazardous items.',
              ),
              _section(
                title: 'Wallet & Payments',
                icon: Icons.account_balance_wallet_outlined,
                content:
                    'Wallet balances, delivery fees, payouts, and platform fees are governed by the terms in effect at the time of each transaction. Eziza may withhold, reverse, or investigate transactions reasonably suspected to be fraudulent or made in error.',
              ),
              _section(
                title: 'Intellectual Property',
                icon: Icons.copyright_outlined,
                content:
                    'All software, content, trademarks, branding and intellectual property associated with Eziza remain the exclusive property of Eziza.',
              ),
              _section(
                title: 'Account Deletion & Termination',
                icon: Icons.cancel_outlined,
                content:
                    'You may permanently delete your account at any time from Account settings. Your access to Eziza may also be terminated if you violate any part of this agreement or misuse the platform.',
              ),
              _section(
                title: 'Governing Law',
                icon: Icons.balance_outlined,
                content:
                    'This agreement shall be governed and interpreted in accordance with the applicable laws of Nigeria.',
              ),
              const SizedBox(height: 14),
              _footerCard(),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _hero() => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [EzizaColors.kPurpleD, EzizaColors.kNavy],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(color: Color(0x446C3483), blurRadius: 16, offset: Offset(0, 6))
            ]),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
            child: Row(children: [
              GestureDetector(
                onTap: () => Get.back(),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration:
                      BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('End-User License Agreement',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 3),
                  Text('Your rights & responsibilities on Eziza',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 20),
              ),
            ]),
          ),
        ),
      );

  Widget _mainCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [
            BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: const Text(
          'This End-User License Agreement ("EULA") is a legal agreement between you and Eziza. '
          'By creating an account or using the Eziza application, you agree to be bound by the terms of this agreement.',
          style: TextStyle(fontSize: 14, height: 1.7, color: EzizaColors.kText),
        ),
      );

  Widget _section({required String title, required IconData icon, required String content}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EzizaColors.kBorder),
          boxShadow: [
            BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: EzizaColors.kPurple, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: EzizaColors.kText)),
              const SizedBox(height: 6),
              Text(content, style: const TextStyle(fontSize: 12.5, color: EzizaColors.kMuted, height: 1.6)),
            ]),
          ),
        ]),
      );

  Widget _footerCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [EzizaColors.kSurface, EzizaColors.kBorder.withValues(alpha: 0.5)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EzizaColors.kBorder),
        ),
        child: Column(children: [
          const Icon(Icons.shield_moon_outlined, color: EzizaColors.kPurple, size: 32),
          const SizedBox(height: 12),
          const Text('Your privacy and trust matter to us.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: EzizaColors.kText)),
          const SizedBox(height: 6),
          const Text('Eziza continuously works to provide a secure and transparent logistics platform.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: EzizaColors.kMuted, height: 1.6)),
        ]),
      );
}
