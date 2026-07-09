import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../main.dart';

/// One shared page for all 3 roles (rider/company/customer) -- Apple App
/// Store Guideline 5.1.1(v) requires in-app account deletion for any app
/// that supports account creation. Calls the delete-account edge function,
/// which anonymises personal data and permanently bans the account rather
/// than hard-deleting it (see that function's comment for why -- deleting
/// auth.users fails outright for anyone with delivery/wallet history, a
/// hard DB constraint, not a design choice).
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _confirmCtrl = TextEditingController();
  bool _deleting = false;
  bool get _confirmed => _confirmCtrl.text.trim().toUpperCase() == 'DELETE';

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_confirmed) return;
    setState(() => _deleting = true);
    try {
      final res = await Supabase.instance.client.functions.invoke('delete-account');
      final body = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (res.status != 200 || body['ok'] != true) {
        throw Exception(body['error'] ?? 'Could not delete account (${res.status})');
      }
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Get.offAll(() => const AuthRouter());
      Get.snackbar('Account Deleted', 'Your account has been permanently removed.',
          backgroundColor: EzizaColors.kNavy, colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 5));
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      Get.snackbar('Could not delete account', 'Please try again, or contact support.',
          backgroundColor: EzizaColors.kError, colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(16));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: SingleChildScrollView(
        child: Column(children: [
          _hero(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: EzizaColors.kError.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: EzizaColors.kError.withValues(alpha: 0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.warning_amber_rounded, color: EzizaColors.kError, size: 18),
                    SizedBox(width: 8),
                    Text('This cannot be undone',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: EzizaColors.kError)),
                  ]),
                  const SizedBox(height: 10),
                  _bullet('You will be permanently signed out and can never log back into this account.'),
                  _bullet('Your name, phone, photo, and (for riders/companies) documents and bank details will be permanently removed.'),
                  _bullet('Delivery, payment, and rating records that involve other people are kept for legal and accounting reasons, but are no longer linked to your personal information.'),
                ]),
              ),
              const SizedBox(height: 24),
              const Text('Type DELETE to confirm',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: EzizaColors.kText)),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: EzizaColors.kText, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: const TextStyle(color: EzizaColors.kMuted),
                  filled: true,
                  fillColor: EzizaColors.kWhite,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kError, width: 1.5)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_confirmed && !_deleting) ? _delete : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EzizaColors.kError,
                    disabledBackgroundColor: EzizaColors.kMuted.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _deleting
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Permanently Delete My Account',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: EzizaColors.kError),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: EzizaColors.kText, height: 1.45)),
          ),
        ]),
      );

  Widget _hero() => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [EzizaColors.kNavy, Color(0xFF3E0D0D)],
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
                  Text('Delete Account',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 3),
                  Text('Permanently remove your Eziza account',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 20),
              ),
            ]),
          ),
        ),
      );
}
