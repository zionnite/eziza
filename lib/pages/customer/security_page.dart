import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import 'change_transaction_pin.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final _db = Supabase.instance.client;

  bool _fingerprintEnabled = false;
  bool _pinSet = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _db.auth.currentUser?.id;
    bool pinSet = false;
    if (uid != null) {
      try {
        final row = await _db.from('customers').select('pin_set').eq('id', uid).single();
        pinSet = row['pin_set'] as bool? ?? false;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _fingerprintEnabled = prefs.getBool('fingerprintAuth') ?? false;
        _pinSet = pinSet;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !_fingerprintEnabled;
    await prefs.setBool('fingerprintAuth', newValue);
    setState(() => _fingerprintEnabled = newValue);
    Get.snackbar(
      newValue ? 'Fingerprint Enabled ✓' : 'Fingerprint Disabled',
      newValue
          ? 'You can now use Face ID / fingerprint to confirm wallet payments'
          : 'Biometric authentication has been disabled',
      backgroundColor: Colors.black,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        title: const Text('Security'),
        backgroundColor: EzizaColors.kWhite,
        foregroundColor: EzizaColors.kText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionLabel('Wallet Protection'),
                const SizedBox(height: 10),
                _card(children: [
                  _tile(
                    icon: Icons.pin_outlined,
                    iconColor: EzizaColors.kPurpleD,
                    iconBg: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                    title: 'Change Transaction PIN',
                    subtitle: _pinSet ? 'PIN is set' : 'Not set yet — set one to pay from your wallet',
                    onTap: () async {
                      await Get.to(() => const ChangeTransactionPin());
                      _load();
                    },
                  ),
                  _divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            color: EzizaColors.kPurpleD.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.fingerprint_rounded,
                            color: EzizaColors.kPurpleD, size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Fingerprint / Face ID',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14, color: EzizaColors.kText)),
                          SizedBox(height: 2),
                          Text('Use biometrics instead of your PIN to confirm payments',
                              style: TextStyle(fontSize: 11, color: EzizaColors.kMuted)),
                        ]),
                      ),
                      Switch(
                        value: _fingerprintEnabled,
                        onChanged: (_) => _toggleFingerprint(),
                        activeTrackColor: EzizaColors.kPurple,
                      ),
                    ]),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _sectionLabel(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: EzizaColors.kMuted, letterSpacing: 1.2)),
      );

  Widget _card({required List<Widget> children}) => Container(
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EzizaColors.kBorder),
            boxShadow: [
              BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.05),
                  blurRadius: 8, offset: const Offset(0, 3))
            ]),
        child: Column(children: children),
      );

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14, color: EzizaColors.kText)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: EzizaColors.kMuted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: EzizaColors.kMuted),
          ]),
        ),
      );

  Widget _divider() => Divider(height: 1, indent: 70, endIndent: 16, color: Colors.grey.shade100);
}
