import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../main.dart';

/// Reached only via the eziza://reset deep link after tapping the emailed
/// reset link (Supabase exchanges the link for a recovery session before
/// this page ever opens -- auth.updateUser() then just sets the new
/// password on that session). Ported from ZeeFashion's reset_password.dart.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> with SingleTickerProviderStateMixin {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConf = true;

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
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_passCtrl.text.isEmpty) {
      Get.snackbar('Oops', 'Enter your new password', backgroundColor: EzizaColors.kPurple, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_passCtrl.text.length < 8) {
      Get.snackbar('Oops', 'Password must be at least 8 characters', backgroundColor: EzizaColors.kError, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      Get.snackbar('Oops', 'Passwords do not match', backgroundColor: EzizaColors.kError, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _passCtrl.text));
      if (!mounted) return;
      Get.snackbar('Password Updated', 'Your password has been changed successfully.', backgroundColor: EzizaColors.kPurple, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Get.offAll(() => const AuthRouter());
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      Get.snackbar('Oops', 'Could not update password', backgroundColor: EzizaColors.kError, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
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
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [EzizaColors.kPurple.withValues(alpha: 0.08), Colors.transparent])),
          ),
        ),
        Positioned(
          bottom: -60, left: -60,
          child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [EzizaColors.kGold.withValues(alpha: 0.07), Colors.transparent])),
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
                    const SizedBox(height: 52),
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: EzizaColors.kBorder)),
                      child: const Icon(Icons.lock_reset_rounded, size: 26, color: EzizaColors.kPurple),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(width: 14, height: 2, decoration: BoxDecoration(color: EzizaColors.kPurple, borderRadius: BorderRadius.circular(1)), margin: const EdgeInsets.only(right: 8)),
                      Text('SECURITY', style: TextStyle(color: EzizaColors.kPurple.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                    ]),
                    const SizedBox(height: 10),
                    const Text('Set New\nPassword', style: TextStyle(color: EzizaColors.kText, fontSize: 34, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text('Choose a strong password for your account', style: TextStyle(color: EzizaColors.kMuted, fontSize: 14, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 40),
                    _passField(
                      label: 'New Password',
                      controller: _passCtrl,
                      obscure: _obscurePass,
                      onToggle: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    const SizedBox(height: 16),
                    _passField(
                      label: 'Confirm Password',
                      controller: _confirmCtrl,
                      obscure: _obscureConf,
                      onToggle: () => setState(() => _obscureConf = !_obscureConf),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: EzizaColors.kBorder)),
                      child: Row(children: [
                        Icon(Icons.info_outline, size: 14, color: EzizaColors.kPurple.withValues(alpha: 0.7)),
                        const SizedBox(width: 8),
                        Text('Password must be at least 8 characters', style: TextStyle(color: EzizaColors.kPurple.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500)),
                      ]),
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
                              : const Text('Update Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.3)),
                        ),
                      ),
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

  Widget _passField({required String label, required TextEditingController controller, required bool obscure, required VoidCallback onToggle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: EzizaColors.kText.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: EzizaColors.kBorder, width: 1.2)),
          child: Row(children: [
            const Icon(Icons.lock_outline_rounded, size: 18, color: EzizaColors.kMuted),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
                decoration: InputDecoration(border: InputBorder.none, hintText: label == 'New Password' ? 'Enter new password' : 'Repeat new password', hintStyle: TextStyle(color: EzizaColors.kMuted.withValues(alpha: 0.8), fontSize: 14)),
              ),
            ),
            GestureDetector(
              onTap: onToggle,
              child: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: EzizaColors.kMuted),
            ),
          ]),
        ),
      ],
    );
  }
}
