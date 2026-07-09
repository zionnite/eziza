import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../main.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  final _auth = Get.find<AuthController>();

  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    final result = await _auth.signIn(email, password);
    if (!mounted) return;
    if (result == 'true') {
      // LoginPage/WelcomePage are pushed routes on top of AuthRouter, not
      // its inline build output -- AuthRouter's Obx updates reactively
      // underneath, but that's invisible until we actually clear back to
      // it. Without this, login silently "does nothing" from the user's
      // perspective even though the sign-in succeeded.
      Get.offAll(() => const AuthRouter());
    } else {
      Get.snackbar('Error', result,
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kWhite,
      body: Stack(children: [
        // ── Soft purple glow top-right ──────────────────────────
        Positioned(
          top: -80, right: -80,
          child: Container(
            width: 260, height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [EzizaColors.kPurple.withValues(alpha: 0.08), Colors.transparent]),
            ),
          ),
        ),
        // ── Gold glow bottom-right ──────────────────────────────
        Positioned(
          bottom: 80, right: -50,
          child: Container(
            width: 180, height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [EzizaColors.kGold.withValues(alpha: 0.07), Colors.transparent]),
            ),
          ),
        ),

        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // ── Back ───────────────────────────────────
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: EzizaColors.kSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: EzizaColors.kBorder),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new, size: 15, color: EzizaColors.kText),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Header ─────────────────────────────────
                    Row(children: [
                      Container(
                        width: 14, height: 2,
                        decoration: BoxDecoration(color: EzizaColors.kPurple, borderRadius: BorderRadius.circular(1)),
                        margin: const EdgeInsets.only(right: 8),
                      ),
                      Text('WELCOME BACK',
                          style: TextStyle(color: EzizaColors.kPurple.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                    ]),

                    const SizedBox(height: 10),

                    const Text('Sign In',
                        style: TextStyle(color: EzizaColors.kText, fontSize: 34, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5)),

                    const SizedBox(height: 6),

                    const Text('Good to have you back', style: TextStyle(color: EzizaColors.kMuted, fontSize: 14, fontWeight: FontWeight.w400)),

                    const SizedBox(height: 40),

                    // ── Email ──────────────────────────────────
                    _fieldWrap(
                      label: 'Email Address',
                      child: Row(children: [
                        const Icon(Icons.email_outlined, size: 18, color: EzizaColors.kMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
                            decoration: InputDecoration(border: InputBorder.none, hintText: 'Enter email address', hintStyle: TextStyle(color: EzizaColors.kMuted.withValues(alpha: 0.8), fontSize: 14)),
                          ),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 16),

                    // ── Password ───────────────────────────────
                    _fieldWrap(
                      label: 'Password',
                      child: Row(children: [
                        const Icon(Icons.lock_outline_rounded, size: 18, color: EzizaColors.kMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _password,
                            obscureText: _obscure,
                            style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
                            decoration: InputDecoration(border: InputBorder.none, hintText: 'Enter password', hintStyle: TextStyle(color: EzizaColors.kMuted.withValues(alpha: 0.8), fontSize: 14)),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _obscure = !_obscure),
                          child: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: EzizaColors.kMuted),
                        ),
                      ]),
                    ),

                    // ── Forgot / register links ────────────────
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Get.to(() => const ForgotPasswordPage()),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0)),
                        child: Text('Forgot Password?', style: TextStyle(color: EzizaColors.kPurple.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Submit
                    Obx(() => GestureDetector(
                      onTap: _auth.loading.value ? null : _submit,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: _auth.loading.value ? [Colors.grey.shade300, Colors.grey.shade300] : [EzizaColors.kPurpleD, EzizaColors.kPurple], begin: Alignment.centerLeft, end: Alignment.centerRight),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _auth.loading.value ? [] : [BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 5))],
                        ),
                        child: Center(
                          child: _auth.loading.value
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: EzizaColors.kWhite, strokeWidth: 2))
                              : const Text('Sign In', style: TextStyle(color: EzizaColors.kWhite, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3)),
                        ),
                      ),
                    )),

                    const SizedBox(height: 32),

                    // ── Register link ───────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account?", style: TextStyle(color: EzizaColors.kMuted, fontSize: 14)),
                        TextButton(
                          onPressed: () => Get.to(() => const RegisterPage(), transition: Transition.rightToLeft),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                          child: const Text('Register', style: TextStyle(color: EzizaColors.kPurple, fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _fieldWrap({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: EzizaColors.kText.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: EzizaColors.kBorder, width: 1.2)),
          child: child,
        ),
      ],
    );
  }
}
