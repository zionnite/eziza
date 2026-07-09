import 'package:flutter/material.dart';
import 'package:flutter_otp_text_field/flutter_otp_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/colors.dart';
import '../services/local_auth_services.dart';
import '../utils/currency.dart';

/// Mirrors ZeeFashion's PinVerificationSheet — gates a wallet-spend action
/// behind the customer's transaction PIN (plaintext, matching ZeeFashion's
/// storage pattern), with an optional biometric shortcut if the user has
/// enabled it in Security settings.
class PinVerificationSheet extends StatefulWidget {
  const PinVerificationSheet({
    super.key,
    required this.amount,
    this.label = 'will be deducted from your wallet',
  });

  final double amount;
  final String label;

  /// Show the sheet and return `true` on success (PIN or biometric),
  /// or null if cancelled.
  static Future<bool?> verify(
    BuildContext context, {
    required double amount,
    String label = 'will be deducted from your wallet',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PinVerificationSheet(amount: amount, label: label),
    );
  }

  @override
  State<PinVerificationSheet> createState() => _PinVerificationSheetState();
}

class _PinVerificationSheetState extends State<PinVerificationSheet> {
  final _db = Supabase.instance.client;

  String? _pin;
  bool _verifying = false;
  bool _fingerprintEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkFingerprint();
  }

  Future<void> _checkFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _fingerprintEnabled = prefs.getBool('fingerprintAuth') ?? false);
    }
  }

  String _fmt(double v) => formatNaira(v);

  Future<void> _confirmPin() async {
    if (_pin == null || _pin!.length < 4) {
      setState(() => _error = 'Please enter your 4-digit PIN');
      return;
    }
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final row = await _db.from('customers').select('pin').eq('id', uid).single();
      final storedPin = row['pin']?.toString() ?? '';
      if (storedPin.isNotEmpty && storedPin == _pin) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _error = 'Incorrect PIN. Please try again.';
          _pin = null;
          _verifying = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Could not verify PIN. Please try again.';
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: EzizaColors.kBorder, borderRadius: BorderRadius.circular(2))),

          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                        blurRadius: 10, offset: const Offset(0, 4))
                  ]),
              child: const Icon(Icons.lock_outline_rounded, size: 28, color: Colors.white)),
          const SizedBox(height: 16),

          const Text('Confirm Payment',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: EzizaColors.kText)),
          const SizedBox(height: 8),

          Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3D1A6E), EzizaColors.kNavy]),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(_fmt(widget.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white))),
          const SizedBox(height: 6),
          Text(widget.label, style: const TextStyle(fontSize: 12, color: EzizaColors.kMuted)),
          const SizedBox(height: 28),

          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Enter Transaction PIN',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: EzizaColors.kText))),
          const SizedBox(height: 12),

          OtpTextField(
            numberOfFields: 4,
            borderColor: EzizaColors.kBorder,
            enabledBorderColor: EzizaColors.kBorder,
            focusedBorderColor: EzizaColors.kPurple,
            showFieldAsBox: true,
            fieldWidth: 62,
            borderRadius: BorderRadius.circular(12),
            filled: true,
            fillColor: EzizaColors.kSurface,
            textStyle: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: EzizaColors.kText),
            onCodeChanged: (_) => setState(() => _error = null),
            onSubmit: (code) => setState(() => _pin = code),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFDECEA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: EzizaColors.kError.withValues(alpha: 0.3))),
                child: Row(children: [
                  Icon(Icons.error_outline, color: EzizaColors.kError, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(color: EzizaColors.kError, fontSize: 13))),
                ])),
          ],
          const SizedBox(height: 28),

          GestureDetector(
              onTap: _verifying ? null : _confirmPin,
              child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                      gradient: _verifying
                          ? null
                          : const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                      color: _verifying ? EzizaColors.kBorder : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _verifying
                          ? null
                          : [
                              BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.35),
                                  blurRadius: 12, offset: const Offset(0, 4))
                            ]),
                  child: _verifying
                      ? const Center(
                          child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: EzizaColors.kPurpleD)))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Confirm Payment',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        ]))),

          if (_fingerprintEnabled) ...[
            const SizedBox(height: 14),
            GestureDetector(
                onTap: _verifying
                    ? null
                    : () async {
                        final authenticated = await LocalAuth.authenticate();
                        if (!context.mounted) return;
                        if (authenticated) Navigator.pop(context, true);
                      },
                child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        color: EzizaColors.kPurple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: EzizaColors.kPurple.withValues(alpha: 0.25))),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.fingerprint_rounded, size: 22, color: EzizaColors.kPurpleD),
                      SizedBox(width: 10),
                      Text('Use Fingerprint / Face ID',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600, color: EzizaColors.kPurpleD)),
                    ]))),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
