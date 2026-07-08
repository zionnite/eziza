import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';

/// One shared page for all 3 roles (rider/company/customer) — mirrors
/// ZeeFashion's change_password.dart exactly, including its one notable
/// behavior: "current password" is collected and validated as non-empty,
/// but never actually verified against the account — auth.updateUser()
/// doesn't require it. Matching that intentionally per the roadmap's
/// explicit note to mirror ZeeFashion unless told otherwise.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _db = Supabase.instance.client;
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _error1 = false;
  bool _error2 = false;
  bool _error3 = false;
  bool _mismatch = false;
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text.trim();
    final newPass = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    setState(() {
      _error1 = current.isEmpty;
      _error2 = newPass.isEmpty;
      _error3 = confirm.isEmpty;
      _mismatch = newPass.isNotEmpty && confirm.isNotEmpty && newPass != confirm;
    });
    if (_error1 || _error2 || _error3 || _mismatch) return;

    setState(() => _saving = true);
    try {
      await _db.auth.updateUser(UserAttributes(password: newPass));
      if (!mounted) return;
      Get.back();
      Future.delayed(const Duration(milliseconds: 100), () {
        Get.snackbar('Password Updated ✓', 'Your password has been changed successfully',
            backgroundColor: EzizaColors.kPurpleD,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
            margin: const EdgeInsets.all(16),
            borderRadius: 12,
            duration: const Duration(seconds: 4),
            icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 22));
      });
    } catch (e) {
      Get.snackbar('Oops!', e.toString(),
          backgroundColor: EzizaColors.kError,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
          borderRadius: 12,
          duration: const Duration(seconds: 4));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: SingleChildScrollView(
        child: Column(children: [
          _hero(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: EzizaColors.kPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: EzizaColors.kPurple.withValues(alpha: 0.15))),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: EzizaColors.kPurple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.security_rounded, color: EzizaColors.kPurpleD, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Use a strong password with at least 8 characters for better security.',
                        style: TextStyle(fontSize: 12, color: EzizaColors.kMuted, height: 1.4)),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: EzizaColors.kWhite,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: EzizaColors.kBorder),
                    boxShadow: [
                      BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.05),
                          blurRadius: 10, offset: const Offset(0, 4))
                    ]),
                child: Column(children: [
                  _fieldLabel('Current Password'),
                  _passwordField(
                    controller: _currentCtrl,
                    hint: 'Enter your current password',
                    visible: _showCurrent,
                    hasError: _error1,
                    errorText: 'Current password is required',
                    onToggle: () => setState(() => _showCurrent = !_showCurrent),
                    onChanged: (_) => setState(() => _error1 = false),
                  ),
                  const SizedBox(height: 18),
                  _fieldLabel('New Password'),
                  _passwordField(
                    controller: _newCtrl,
                    hint: 'Enter new password',
                    visible: _showNew,
                    hasError: _error2,
                    errorText: 'New password is required',
                    onToggle: () => setState(() => _showNew = !_showNew),
                    onChanged: (_) => setState(() {
                      _error2 = false;
                      _mismatch = false;
                    }),
                  ),
                  const SizedBox(height: 18),
                  _fieldLabel('Confirm New Password'),
                  _passwordField(
                    controller: _confirmCtrl,
                    hint: 'Re-enter new password',
                    visible: _showConfirm,
                    hasError: _error3 || _mismatch,
                    errorText: _mismatch ? 'Passwords do not match' : 'Please confirm your password',
                    onToggle: () => setState(() => _showConfirm = !_showConfirm),
                    onChanged: (_) => setState(() {
                      _error3 = false;
                      _mismatch = false;
                    }),
                  ),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: _saving ? null : _submit,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                                blurRadius: 10, offset: const Offset(0, 4))
                          ]),
                      child: _saving
                          ? const Center(
                              child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                          : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.verified_outlined, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Update Password',
                                  style: TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                            ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ]),
      ),
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
                  Text('Change Password',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 3),
                  Text('Keep your Eziza account secure',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 20),
              ),
            ]),
          ),
        ),
      );

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: EzizaColors.kMuted, letterSpacing: 0.3)),
        ),
      );

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool visible,
    required bool hasError,
    required String errorText,
    required VoidCallback onToggle,
    required Function(String) onChanged,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: controller,
        obscureText: !visible,
        style: const TextStyle(fontSize: 14, color: EzizaColors.kText),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFD1C4E9), fontSize: 14),
          prefixIcon: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: EzizaColors.kPurple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.lock_outline_rounded, color: EzizaColors.kPurple, size: 18),
          ),
          suffixIcon: GestureDetector(
            onTap: onToggle,
            child: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: EzizaColors.kMuted, size: 20),
          ),
          filled: true,
          fillColor: EzizaColors.kSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: EzizaColors.kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hasError ? EzizaColors.kError.withValues(alpha: 0.6) : EzizaColors.kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: hasError ? EzizaColors.kError : EzizaColors.kPurple, width: 1.5)),
        ),
      ),
      if (hasError)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(errorText, style: const TextStyle(color: EzizaColors.kError, fontSize: 12)),
        ),
    ]);
  }
}
