import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../services/bank_service.dart';

enum BankAccountRole { rider, company }

/// Detached Bank Account page, separate from Edit Profile — riders and
/// companies each have their own tile/route into this, own load, own save.
/// Rider bank_name is free text (no bank_code column on riders); company
/// uses the same bank picker company_registration_page.dart uses at signup.
class BankAccountPage extends StatefulWidget {
  final BankAccountRole role;
  const BankAccountPage({super.key, required this.role});

  @override
  State<BankAccountPage> createState() => _BankAccountPageState();
}

class _BankAccountPageState extends State<BankAccountPage> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _bankNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();

  List<Bank> _banks = [];
  Bank? _selectedBank;
  String? _companyId;

  bool _loading = true;
  bool _saving = false;

  bool get _isCompany => widget.role == BankAccountRole.company;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isCompany) {
      final uid = _db.auth.currentUser?.id;
      if (uid != null) {
        try {
          final row =
              await _db.from('companies').select().eq('auth_user_id', uid).single();
          final banks = await BankService.fetchBanks();
          _companyId = row['id'] as String;
          _accountNumberCtrl.text = row['account_number'] as String? ?? '';
          _accountNameCtrl.text = row['account_name'] as String? ?? '';
          _banks = banks;
          final bankCode = row['bank_code'] as String?;
          if (bankCode != null) {
            _selectedBank = banks.firstWhereOrNull((b) => b.code == bankCode) ??
                Bank(name: row['bank_name'] as String? ?? '', code: bankCode);
          }
        } catch (_) {}
      }
    } else {
      final rider = Get.find<AuthController>().rider.value;
      _bankNameCtrl.text = rider?.bankName ?? '';
      _accountNumberCtrl.text = rider?.accountNumber ?? '';
      _accountNameCtrl.text = rider?.accountName ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg) => Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      backgroundColor: EzizaColors.kPurple,
      colorText: EzizaColors.kWhite,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16));

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isCompany && _selectedBank == null) {
      _snack('Please select a bank.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isCompany) {
        if (_companyId == null) return;
        await _db.from('companies').update({
          'bank_name': _selectedBank?.name,
          'bank_code': _selectedBank?.code,
          'account_number': _accountNumberCtrl.text.trim(),
          'account_name': _accountNameCtrl.text.trim(),
        }).eq('id', _companyId!);
        if (!mounted) return;
        _snack('Bank account updated.');
      } else {
        final result = await Get.find<AuthController>().updateBankDetails(
          bankName: _bankNameCtrl.text.trim(),
          accountNumber: _accountNumberCtrl.text.trim(),
          accountName: _accountNameCtrl.text.trim(),
        );
        if (!mounted) return;
        if (result == 'true') {
          _snack('Bank account updated.');
        } else {
          _snack(result);
        }
      }
    } catch (_) {
      if (mounted) _snack('Could not update bank account. Please try again.');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
          : SingleChildScrollView(
              child: Column(children: [
                _hero(),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            child: const Icon(Icons.info_outline_rounded,
                                color: EzizaColors.kPurpleD, size: 18),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                                'This is where your earnings are paid out to. Make sure the details are correct.',
                                style: TextStyle(fontSize: 12, color: EzizaColors.kMuted, height: 1.4)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 24),
                      if (_isCompany) _bankPicker() else _bankNameField(),
                      const SizedBox(height: 12),
                      _field(
                        controller: _accountNumberCtrl,
                        label: 'Account Number',
                        icon: Icons.tag_rounded,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (v) {
                          final val = v?.trim() ?? '';
                          if (val.isEmpty) return 'Required';
                          if (val.length != 10) return 'Must be exactly 10 digits';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _accountNameCtrl,
                        label: 'Account Name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [EzizaColors.kPurpleD, EzizaColors.kPurple]),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.3),
                                    blurRadius: 10, offset: const Offset(0, 4))
                              ]),
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            child: _saving
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Save Changes',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ]),
                  ),
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
                  Text('Bank Account',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 3),
                  Text('Where your payouts are sent',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
              ),
            ]),
          ),
        ),
      );

  Widget _bankPicker() {
    return DropdownButtonFormField<Bank>(
      initialValue: _selectedBank,
      isExpanded: true,
      items: _banks
          .map((b) => DropdownMenuItem(value: b, child: Text(b.name, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (b) => setState(() => _selectedBank = b),
      decoration: InputDecoration(
        labelText: 'Bank',
        labelStyle: const TextStyle(color: EzizaColors.kMuted),
        prefixIcon: const Icon(Icons.account_balance_outlined, color: EzizaColors.kMuted, size: 20),
        filled: true,
        fillColor: EzizaColors.kSurface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kPurple, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _bankNameField() => _field(
        controller: _bankNameCtrl,
        label: 'Bank Name',
        icon: Icons.account_balance_outlined,
        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
      );

  TextFormField _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: const TextStyle(color: EzizaColors.kText),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: EzizaColors.kMuted),
          prefixIcon: Icon(icon, color: EzizaColors.kMuted, size: 20),
          filled: true,
          fillColor: EzizaColors.kSurface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: EzizaColors.kPurple, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kError)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
