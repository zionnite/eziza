import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants/colors.dart';
import 'welcome_page.dart';

/// First-run intro carousel. Structurally ported from ZeeFashion's
/// onboarding_screen.dart (full-bleed layer + gradient overlay + glass
/// bottom card + page dots), but Eziza has no photography assets, so the
/// "full-bleed layer" is a gradient + large icon instead of a photo -- same
/// visual weight, matches the icon+gradient hero language already used
/// throughout the rest of the app (profile/bank/change-password pages).
class _Slide {
  final IconData icon;
  final String tagline;
  final String title;
  final String subtitle;
  final Color accent;
  final List<Color> bg;

  const _Slide({
    required this.icon,
    required this.tagline,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.bg,
  });
}

const _slides = [
  _Slide(
    icon: Icons.local_shipping_rounded,
    tagline: 'WELCOME TO EZIZA',
    title: 'Send Anything,\nAnywhere,\nFast',
    subtitle: 'Request a pickup in seconds and get matched with a nearby rider or logistics company.',
    accent: EzizaColors.kGold,
    bg: [EzizaColors.kNavy, Color(0xFF1A1A6E), EzizaColors.kPurpleD],
  ),
  _Slide(
    icon: Icons.location_on_rounded,
    tagline: 'REAL-TIME TRACKING',
    title: 'Watch Your\nPackage\nMove Live',
    subtitle: 'Track your rider on the map from pickup to drop-off, with status updates every step of the way.',
    accent: EzizaColors.kTeal,
    bg: [EzizaColors.kNavy, Color(0xFF0A2050), EzizaColors.kPurpleD],
  ),
  _Slide(
    icon: Icons.payments_rounded,
    tagline: 'RIDERS & COMPANIES',
    title: 'Earn on\nYour Own\nSchedule',
    subtitle: 'Bid on delivery jobs, get paid straight to your wallet, and cash out whenever you\'re ready.',
    accent: EzizaColors.kGold,
    bg: [EzizaColors.kNavy, EzizaColors.kPurpleD, EzizaColors.kPurple],
  ),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> with TickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _page = 0;

  late final AnimationController _entrance;
  late final AnimationController _float;
  late final Animation<double> _fadeA;
  late final Animation<Offset> _slideA;
  late final Animation<double> _floatA;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _float = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);

    _fadeA = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slideA = Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _floatA = Tween<double>(begin: 0, end: 10).animate(CurvedAnimation(parent: _float, curve: Curves.easeInOut));

    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _float.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    _entrance.forward(from: 0);
  }

  Future<void> _finish() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.onboarding_done');
      await file.create(recursive: true);
    } catch (_) {}
    if (!mounted) return;
    Get.offAll(() => const WelcomePage(),
        transition: Transition.fadeIn, duration: const Duration(milliseconds: 700));
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 750), curve: Curves.easeInOutCubic);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final slide = _slides[_page];
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: EzizaColors.kNavy,
      body: Stack(children: [
        // ── 1. Full-bleed gradient layer (swipeable) ─────────────
        PageView.builder(
          controller: _pageCtrl,
          onPageChanged: _onPageChanged,
          itemCount: _slides.length,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (_, i) => _BgLayer(slide: _slides[i], size: size),
        ),

        // ── 2. Floating accent orbs ───────────────────────────────
        AnimatedBuilder(
          animation: _floatA,
          builder: (_, _) => _Orbs(slide: slide, size: size, float: _floatA.value),
        ),

        // ── 3. Center icon ────────────────────────────────────────
        Positioned(
          top: size.height * 0.16,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Container(
                key: ValueKey(_page),
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(color: slide.accent.withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: slide.accent.withValues(alpha: 0.25), blurRadius: 40, spreadRadius: 4),
                  ],
                ),
                child: Icon(slide.icon, size: 62, color: slide.accent),
              ),
            ),
          ),
        ),

        // ── 4. Top bar: logo + skip ───────────────────────────────
        Positioned(
          top: padding.top + 14,
          left: 24,
          right: 20,
          child: FadeTransition(
            opacity: _fadeA,
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [slide.accent, slide.accent.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [BoxShadow(color: slide.accent.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.bolt_rounded, size: 18, color: Colors.black),
              ),
              const SizedBox(width: 10),
              const Text('Eziza',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              const Spacer(),
              if (!isLast)
                GestureDetector(
                  onTap: _finish,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Text('Skip',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                  ),
                ),
            ]),
          ),
        ),

        // ── 5. Glass card at bottom ───────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: EdgeInsets.fromLTRB(28, 26, 28, padding.bottom + 28),
                decoration: BoxDecoration(
                  color: EzizaColors.kNavy.withValues(alpha: 0.7),
                  border: Border(top: BorderSide(color: slide.accent.withValues(alpha: 0.15), width: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _fadeA,
                      child: Row(children: [
                        Container(width: 20, height: 1.5, color: slide.accent, margin: const EdgeInsets.only(right: 8)),
                        Text(slide.tagline,
                            style: TextStyle(color: slide.accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    SlideTransition(
                      position: _slideA,
                      child: FadeTransition(
                        opacity: _fadeA,
                        child: Text(slide.title,
                            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -0.6)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SlideTransition(
                      position: _slideA,
                      child: FadeTransition(
                        opacity: _fadeA,
                        child: Text(slide.subtitle,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14, height: 1.6, fontWeight: FontWeight.w400)),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Row(children: [
                      Row(children: List.generate(_slides.length, (i) {
                        final active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.only(right: 6),
                          width: active ? 24 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: active ? slide.accent : Colors.white.withValues(alpha: 0.2),
                            boxShadow: active ? [BoxShadow(color: slide.accent.withValues(alpha: 0.5), blurRadius: 6)] : null,
                          ),
                        );
                      })),
                      const Spacer(),
                      if (_page > 0)
                        GestureDetector(
                          onTap: () => _pageCtrl.previousPage(duration: const Duration(milliseconds: 750), curve: Curves.easeInOutCubic),
                          child: Container(
                            width: 48,
                            height: 48,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.08),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: Icon(Icons.arrow_back_rounded, color: Colors.white.withValues(alpha: 0.7), size: 18),
                          ),
                        ),
                      GestureDetector(
                        onTap: _next,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          padding: EdgeInsets.symmetric(horizontal: isLast ? 24 : 18, vertical: 15),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [slide.accent, slide.accent == EzizaColors.kGold ? const Color(0xFFFF9500) : const Color(0xFF0096B4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [BoxShadow(color: slide.accent.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (isLast) ...[
                              const Text('Get Started',
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.3)),
                              const SizedBox(width: 8),
                            ],
                            const Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 20),
                          ]),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _BgLayer extends StatelessWidget {
  final _Slide slide;
  final Size size;
  const _BgLayer({required this.slide, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: slide.bg, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
    );
  }
}

class _Orbs extends StatelessWidget {
  final _Slide slide;
  final Size size;
  final double float;
  const _Orbs({required this.slide, required this.size, required this.float});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        top: size.height * 0.04 + float * 0.6,
        right: -size.width * 0.12,
        child: Container(
          width: size.width * 0.55,
          height: size.width * 0.55,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [slide.accent.withValues(alpha: 0.07), Colors.transparent]),
          ),
        ),
      ),
      Positioned(
        top: size.height * 0.55 - float * 0.4,
        left: -size.width * 0.08,
        child: Container(
          width: size.width * 0.35,
          height: size.width * 0.35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [EzizaColors.kPurple.withValues(alpha: 0.12), Colors.transparent]),
          ),
        ),
      ),
    ]);
  }
}
