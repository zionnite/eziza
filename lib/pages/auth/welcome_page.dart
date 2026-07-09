import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../constants/colors.dart';
import 'login_page.dart';
import 'register_page.dart';

/// Landing page shown to anyone not logged in (fresh install, post-
/// onboarding, or signed out). Ported structurally from ZeeFashion's
/// welcome_page.dart -- hero area + headline + Create Account/Sign In CTAs
/// -- but the hero is a gradient + icon composition instead of a photo,
/// since Eziza has no photography assets (matches onboarding_page.dart's
/// same substitution).
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      backgroundColor: EzizaColors.kNavy,
      body: Stack(children: [
        // ── TOP: hero image — 56% of screen ───────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: size.height * 0.56,
          child: Image.asset(
            'assets/images/d.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),

        // ── Gradient fade hero → dark bottom ──────────────────────
        Positioned(
          top: size.height * 0.30,
          left: 0,
          right: 0,
          height: size.height * 0.30,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, EzizaColors.kNavy.withValues(alpha: 0.6), EzizaColors.kNavy],
              ),
            ),
          ),
        ),

        // ── BOTTOM: dark background ───────────────────────────────
        Positioned(
          top: size.height * 0.56,
          left: 0,
          right: 0,
          bottom: 0,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [EzizaColors.kNavy, Color(0xFF1A0A3E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // ── Purple glow bottom-left ───────────────────────────────
        Positioned(
          bottom: -60,
          left: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [EzizaColors.kPurpleD.withValues(alpha: 0.45), Colors.transparent]),
            ),
          ),
        ),

        // ── Content ──────────────────────────────────────────────
        Positioned.fill(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Column(children: [
                SizedBox(height: padding.top),

                // ── Top bar: logo pill ────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: EzizaColors.kGold.withValues(alpha: 0.15),
                            border: Border.all(color: EzizaColors.kGold.withValues(alpha: 0.5), width: 1),
                          ),
                          child: const Icon(Icons.bolt_rounded, size: 12, color: EzizaColors.kGold),
                        ),
                        const SizedBox(width: 7),
                        const Text('Eziza',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                      ]),
                    ),
                  ]),
                ),

                const Spacer(),

                // ── Brand text ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(width: 14, height: 1.5, color: EzizaColors.kGold, margin: const EdgeInsets.only(right: 8)),
                        Text('LOGISTICS, SIMPLIFIED',
                            style: TextStyle(color: EzizaColors.kGold, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                      ]),
                      const SizedBox(height: 8),
                      const Text('Send It.\nTrack It.\nDone.',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                              letterSpacing: -0.8,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))])),
                      const SizedBox(height: 10),
                      Text('Request a pickup, watch it move live,\nand get paid fast as a rider or partner.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14, height: 1.55, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // ── Buttons ───────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(28, 0, 28, padding.bottom + 28),
                  child: Column(children: [
                    _btn(
                      label: 'Create Account',
                      icon: Icons.person_add_outlined,
                      onTap: () => Get.to(() => const RegisterPage()),
                      filled: true,
                    ),
                    const SizedBox(height: 11),
                    _btn(
                      label: 'Sign In',
                      icon: Icons.login_rounded,
                      onTap: () => Get.to(() => const LoginPage()),
                      filled: false,
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _btn({required String label, required IconData icon, required VoidCallback onTap, required bool filled}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(colors: [EzizaColors.kGold, Color(0xFFFFB800)], begin: Alignment.centerLeft, end: Alignment.centerRight)
              : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: filled ? [BoxShadow(color: EzizaColors.kGold.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 5))] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: filled ? EzizaColors.kText : Colors.white),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: filled ? EzizaColors.kText : Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}
