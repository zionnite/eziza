import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../../constants/colors.dart';
import 'welcome_page.dart';

/// First-run intro carousel. Ported structurally from ZeeFashion's
/// onboarding_screen.dart (full-bleed photo + gradient overlay + glass
/// bottom card + page dots) -- now using real delivery/courier photography
/// dropped into assets/images/ rather than the icon+gradient stand-in this
/// page shipped with before those existed.
class _Slide {
  final String image;
  final String tagline;
  final String title;
  final String subtitle;
  final Color accent;
  final List<Color> overlay; // 4 stops: top → bottom

  const _Slide({
    required this.image,
    required this.tagline,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.overlay,
  });
}

const _slides = [
  _Slide(
    image: 'assets/images/a.jpg',
    tagline: 'WELCOME TO EZIZA',
    title: 'Send Anything,\nAnywhere,\nFast',
    subtitle: 'Request a pickup in seconds and get matched with a nearby rider or logistics company.',
    accent: EzizaColors.kGold,
    overlay: [
      Color(0xF00D0D3E),
      Color(0xAA1A1A6E),
      Color(0x554A1480),
      Color(0xF00D0D3E),
    ],
  ),
  _Slide(
    image: 'assets/images/b.jpg',
    tagline: 'REAL-TIME TRACKING',
    title: 'Watch Your\nPackage\nMove Live',
    subtitle: 'Track your rider on the map from pickup to drop-off, with status updates every step of the way.',
    accent: EzizaColors.kTeal,
    overlay: [
      Color(0xF00D0D3E),
      Color(0xAA0A2050),
      Color(0x5500C3E3),
      Color(0xF00D0D3E),
    ],
  ),
  _Slide(
    image: 'assets/images/c.jpg',
    tagline: 'RIDERS & COMPANIES',
    title: 'Earn on\nYour Own\nSchedule',
    subtitle: 'Bid on delivery jobs, get paid straight to your wallet, and cash out whenever you\'re ready.',
    accent: EzizaColors.kGold,
    overlay: [
      Color(0xF00D0D3E),
      Color(0xAA4A1480),
      Color(0x556C3483),
      Color(0xF00D0D3E),
    ],
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
  late final Animation<double> _scaleA;
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
    _scaleA = Tween<double>(begin: 1.06, end: 1.0)
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
        // ── 1. Full-bleed image (swipeable) ─────────────────────
        PageView.builder(
          controller: _pageCtrl,
          onPageChanged: _onPageChanged,
          itemCount: _slides.length,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (_, i) => _ImageLayer(image: _slides[i].image, scaleAnim: _scaleA, size: size),
        ),

        // ── 2. Cinematic gradient overlay ────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.3, 0.6, 1.0],
              colors: slide.overlay,
            ),
          ),
        ),

        // ── 3. Subtle vignette on sides ───────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Colors.transparent, EzizaColors.kNavy.withValues(alpha: 0.55)],
            ),
          ),
        ),

        // ── 4. Floating accent orbs ───────────────────────────────
        AnimatedBuilder(
          animation: _floatA,
          builder: (_, _) => _Orbs(slide: slide, size: size, float: _floatA.value),
        ),

        // ── 5. Top bar: logo + skip ───────────────────────────────
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

        // ── 6. Swipe hint (first page only) ──────────────────────
        if (_page == 0)
          Positioned(
            bottom: padding.bottom + 170,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeA,
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.swipe_rounded, size: 14, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(width: 6),
                  Text('Swipe to explore', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, letterSpacing: 0.5)),
                ]),
              ),
            ),
          ),

        // ── 7. Glass card at bottom ───────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
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
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 20,
                          height: 1.5,
                          decoration: BoxDecoration(color: slide.accent, borderRadius: BorderRadius.circular(1)),
                          margin: const EdgeInsets.only(right: 8),
                        ),
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
                            style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -0.8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SlideTransition(
                      position: _slideA,
                      child: FadeTransition(
                        opacity: _fadeA,
                        child: Text(slide.subtitle,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14, height: 1.65, fontWeight: FontWeight.w400, letterSpacing: 0.1)),
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

class _ImageLayer extends StatelessWidget {
  final String image;
  final Animation<double> scaleAnim;
  final Size size;

  const _ImageLayer({required this.image, required this.scaleAnim, required this.size});

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: scaleAnim,
      child: Image.asset(image, width: size.width, height: size.height, fit: BoxFit.cover, alignment: Alignment.topCenter),
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
        top: size.height * 0.35 - float * 0.4,
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
