import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';

/// Ported from ZeeFashion's forgot_password.dart. Reset link deep-links back
/// into the app via eziza://reset (already-registered scheme, see
/// android/app/src/main/AndroidManifest.xml and ios/Runner/Info.plist),
/// caught by the AppLinks listener wired in main.dart.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      Get.snackbar('Oops', 'Please enter your email address',
          backgroundColor: EzizaColors.kPurple, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email.toLowerCase(),
        redirectTo: 'eziza://reset',
      );
      if (mounted) setState(() { _loading = false; _sent = true; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      Get.snackbar('Oops', 'Could not send reset email. Try again.',
          backgroundColor: EzizaColors.kError, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kWhite,
      body: Stack(children: [
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
        Positioned(
          bottom: -60, left: -60,
          child: Container(
            width: 200, height: 200,
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
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: EzizaColors.kSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: EzizaColors.kBorder),
                      ),
                      child: const Icon(Icons.mail_lock_outlined, size: 26, color: EzizaColors.kPurple),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(width: 14, height: 2, decoration: BoxDecoration(color: EzizaColors.kPurple, borderRadius: BorderRadius.circular(1)), margin: const EdgeInsets.only(right: 8)),
                      Text('ACCOUNT RECOVERY', style: TextStyle(color: EzizaColors.kPurple.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                    ]),
                    const SizedBox(height: 10),
                    const Text('Forgot\nPassword?',
                        style: TextStyle(color: EzizaColors.kText, fontSize: 34, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    Text(
                      _sent ? 'Reset link sent! Check your inbox.' : 'Enter your email and we\'ll send\na password reset link.',
                      style: const TextStyle(color: EzizaColors.kMuted, fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
                    ),
                    const SizedBox(height: 40),
                    if (_sent) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: EzizaColors.kSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: EzizaColors.kBorder),
                        ),
                        child: Column(children: [
                          Container(
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              color: EzizaColors.kPurple.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: EzizaColors.kPurple.withValues(alpha: 0.2)),
                            ),
                            child: const Icon(Icons.mark_email_read_outlined, size: 24, color: EzizaColors.kPurple),
                          ),
                          const SizedBox(height: 14),
                          const Text('Email Sent!', style: TextStyle(color: EzizaColors.kText, fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text('We sent a reset link to\n${_emailCtrl.text.trim()}', textAlign: TextAlign.center, style: const TextStyle(color: EzizaColors.kMuted, fontSize: 13, height: 1.5)),
                          const SizedBox(height: 6),
                          Text('Check your spam folder too', style: TextStyle(color: EzizaColors.kMuted.withValues(alpha: 0.6), fontSize: 11, fontStyle: FontStyle.italic)),
                        ]),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: GestureDetector(
                          onTap: () => setState(() { _sent = false; _emailCtrl.clear(); }),
                          child: Text('Use a different email',
                              style: TextStyle(color: EzizaColors.kPurple.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: EzizaColors.kPurple.withValues(alpha: 0.3))),
                        ),
                      ),
                    ] else ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Email Address', style: TextStyle(color: EzizaColors.kText.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: EzizaColors.kBorder, width: 1.2)),
                            child: Row(children: [
                              const Icon(Icons.email_outlined, size: 18, color: EzizaColors.kMuted),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
                                  decoration: InputDecoration(border: InputBorder.none, hintText: 'Enter email address', hintStyle: TextStyle(color: EzizaColors.kMuted.withValues(alpha: 0.8), fontSize: 14)),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      GestureDetector(
                        onTap: _loading ? null : _submit,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: _loading ? [Colors.grey.shade300, Colors.grey.shade300] : [EzizaColors.kPurple, EzizaColors.kPurpleD], begin: Alignment.centerLeft, end: Alignment.centerRight),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: _loading ? [] : [BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 5))],
                          ),
                          child: Center(
                            child: _loading
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Send Reset Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Remember your password?', style: TextStyle(color: EzizaColors.kMuted, fontSize: 13)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => Get.back(),
                          child: const Text('Sign In', style: TextStyle(color: EzizaColors.kPurple, fontSize: 13, fontWeight: FontWeight.w700)),
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
}
