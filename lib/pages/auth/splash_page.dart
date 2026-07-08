import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants/colors.dart';
import '../../main.dart';
import 'onboarding_page.dart';

/// Brief branded launch screen -- checks the first-run flag (near-instant,
/// file-based) and routes into OnboardingPage on a fresh install or straight
/// into the normal auth-router flow otherwise. Mirrors ZeeFashion's
/// isFirstTime check in main.dart, just moved behind a branded frame instead
/// of a bare loading spinner.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    _decide();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _decide() async {
    bool isFirstTime = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final flagFile = File('${dir.path}/.onboarding_done');
      isFirstTime = !await flagFile.exists();
    } catch (_) {}

    // Keep the brand on screen briefly even when the check resolves instantly.
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    if (isFirstTime) {
      Get.offAll(() => const OnboardingPage(),
          transition: Transition.fadeIn, duration: const Duration(milliseconds: 500));
    } else {
      Get.offAll(() => const AuthRouter(),
          transition: Transition.fadeIn, duration: const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kNavy,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: EzizaColors.kPurple.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 42),
              ),
              const SizedBox(height: 20),
              const Text('Eziza',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Delivery made simple',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}
