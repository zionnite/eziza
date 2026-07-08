import 'package:flutter/material.dart';
import 'package:flutter_otp_text_field/flutter_otp_text_field.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';

class VerifyTransactionPin extends StatefulWidget {
  const VerifyTransactionPin({super.key, required this.lockPin});
  final String lockPin;

  @override
  State<VerifyTransactionPin> createState() => _VerifyTransactionPinState();
}

class _VerifyTransactionPinState extends State<VerifyTransactionPin> {
  final _db = Supabase.instance.client;

  String? _pin;
  bool _pinError = false;
  bool _pinMatchError = false;
  bool _saving = false;

  Future<void> _save() async {
    if (_pin == null || _pin!.length < 4) {
      setState(() => _pinError = true);
      return;
    }
    if (_pin != widget.lockPin) {
      setState(() => _pinMatchError = true);
      return;
    }

    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;

    setState(() {
      _pinError = false;
      _pinMatchError = false;
      _saving = true;
    });

    try {
      await _db.from('customers').update({'pin': _pin, 'pin_set': true}).eq('id', uid);
      if (!mounted) return;
      Get.snackbar('PIN Updated ✓', 'Your transaction PIN has been changed successfully',
          backgroundColor: Colors.black,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
          borderRadius: 10,
          duration: const Duration(seconds: 2),
          icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 22));
      Future.delayed(const Duration(seconds: 1), () {
        Get.back();
        Get.back();
      });
    } catch (_) {
      Get.snackbar('Oops!', 'Could not update PIN. Please try again.',
          backgroundColor: EzizaColors.kError,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
          borderRadius: 10);
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
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: EzizaColors.kWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: EzizaColors.kBorder),
                    boxShadow: [
                      BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.05),
                          blurRadius: 10, offset: const Offset(0, 4))
                    ]),
                child: Column(children: [
                  Container(
                    width: 78, height: 78,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.25),
                              blurRadius: 12, offset: const Offset(0, 5))
                        ]),
                    child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 20),
                  const Text('Confirm Your PIN',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: EzizaColors.kText)),
                  const SizedBox(height: 8),
                  const Text('Re-enter the same 4-digit PIN\nto confirm and save.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: EzizaColors.kMuted, height: 1.5)),
                  const SizedBox(height: 34),
                  OtpTextField(
                    numberOfFields: 4,
                    borderColor: _pinMatchError ? EzizaColors.kError : EzizaColors.kBorder,
                    enabledBorderColor: _pinMatchError ? EzizaColors.kError : EzizaColors.kBorder,
                    focusedBorderColor: _pinMatchError ? EzizaColors.kError : EzizaColors.kPurple,
                    showFieldAsBox: true,
                    fieldWidth: 62,
                    fieldHeight: 64,
                    borderRadius: BorderRadius.circular(14),
                    filled: true,
                    fillColor: _pinMatchError ? const Color(0xFFFDECEA) : EzizaColors.kSurface,
                    textStyle: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, color: EzizaColors.kText),
                    onCodeChanged: (_) => setState(() {
                      _pinError = false;
                      _pinMatchError = false;
                    }),
                    onSubmit: (code) => setState(() => _pin = code),
                  ),
                  if (_pinError) ...[
                    const SizedBox(height: 14),
                    const Text('Please enter your 4-digit PIN',
                        style: TextStyle(color: EzizaColors.kError, fontSize: 12)),
                  ],
                  if (_pinMatchError) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFDECEA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: EzizaColors.kError.withValues(alpha: 0.3))),
                      child: Row(children: [
                        Icon(Icons.error_outline, color: EzizaColors.kError, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('PINs do not match. Go back and try again.',
                              style: TextStyle(color: EzizaColors.kError, fontSize: 12)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _saving ? null : _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                            gradient: _saving
                                ? null
                                : const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                            color: _saving ? EzizaColors.kBorder : null,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: _saving
                                ? null
                                : [
                                    BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.28),
                                        blurRadius: 10, offset: const Offset(0, 4))
                                  ]),
                        child: _saving
                            ? const Center(
                                child: SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: EzizaColors.kPurpleD)))
                            : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                SizedBox(width: 8),
                                Text('Save PIN',
                                    style: TextStyle(
                                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                              ]),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: EzizaColors.kPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: EzizaColors.kPurple.withValues(alpha: 0.15))),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.shield_outlined, color: EzizaColors.kPurple, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Your transaction PIN helps protect your wallet and payments on Eziza.',
                        style: TextStyle(fontSize: 12, color: EzizaColors.kMuted, height: 1.5)),
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration:
                        BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Confirm PIN',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Step 2 of 2 — Confirm your new PIN',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              ]),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
                child: Row(children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Verify Your Transaction PIN',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Re-enter the same 4-digit PIN to securely save your new transaction PIN.',
                          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}
