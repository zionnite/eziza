import 'package:flutter/material.dart';
import 'package:flutter_otp_text_field/flutter_otp_text_field.dart';
import 'package:get/get.dart';

import '../../constants/colors.dart';
import 'verify_transaction_pin.dart';

class ChangeTransactionPin extends StatefulWidget {
  const ChangeTransactionPin({super.key});

  @override
  State<ChangeTransactionPin> createState() => _ChangeTransactionPinState();
}

class _ChangeTransactionPinState extends State<ChangeTransactionPin> {
  String? _pin;
  bool _pinError = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: SingleChildScrollView(
        child: Column(children: [
          _hero(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
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
                    width: 82, height: 82,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [EzizaColors.kPurple, EzizaColors.kPurpleD],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                              blurRadius: 12, offset: const Offset(0, 5))
                        ]),
                    child: const Icon(Icons.pin_outlined, size: 38, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text('Enter Your New PIN',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800, color: EzizaColors.kText)),
                  const SizedBox(height: 8),
                  const Text(
                      "Choose a secure 4-digit PIN you'll remember.\nYou'll confirm it on the next step.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: EzizaColors.kMuted, height: 1.6)),
                  const SizedBox(height: 36),
                  OtpTextField(
                    numberOfFields: 4,
                    borderColor: EzizaColors.kBorder,
                    enabledBorderColor: EzizaColors.kBorder,
                    focusedBorderColor: EzizaColors.kPurple,
                    showFieldAsBox: true,
                    fieldWidth: 64,
                    fieldHeight: 64,
                    borderRadius: BorderRadius.circular(14),
                    filled: true,
                    fillColor: EzizaColors.kSurface,
                    textStyle: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800, color: EzizaColors.kText),
                    onCodeChanged: (_) => setState(() => _pinError = false),
                    onSubmit: (code) => setState(() => _pin = code),
                  ),
                  if (_pinError) ...[
                    const SizedBox(height: 12),
                    const Text('Please enter your 4-digit PIN',
                        style: TextStyle(color: EzizaColors.kError, fontSize: 12)),
                  ],
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () {
                        if (_pin == null || _pin!.length < 4) {
                          setState(() => _pinError = true);
                          return;
                        }
                        Get.to(() => VerifyTransactionPin(lockPin: _pin!));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                                  blurRadius: 10, offset: const Offset(0, 4))
                            ]),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('Continue',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: EzizaColors.kPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EzizaColors.kPurple.withValues(alpha: 0.15))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.security_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                        'Your transaction PIN helps protect wallet payments and top-ups on Eziza.',
                        style: TextStyle(fontSize: 12, color: EzizaColors.kMuted, height: 1.5)),
                  ),
                ]),
              ),
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
            child: Row(children: [
              GestureDetector(
                onTap: () => Get.back(),
                child: Container(
                  width: 42, height: 42,
                  decoration:
                      BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Change Transaction PIN',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Step 1 of 2 — Set new PIN',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 22),
              ),
            ]),
          ),
        ),
      );
}
