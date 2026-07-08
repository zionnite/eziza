import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/colors.dart';
import '../../services/wallet_service.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _db = Supabase.instance.client;

  double _balance = 0;
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  bool _topUpLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        WalletService.getBalance(uid),
        WalletService.getTransactions(uid),
      ]);
      if (mounted) {
        setState(() {
          _balance = results[0] as double;
          _transactions = results[1] as List<Map<String, dynamic>>;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg) => Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      backgroundColor: EzizaColors.kPurple,
      colorText: EzizaColors.kWhite,
      snackPosition: SnackPosition.BOTTOM);

  Future<void> _startTopUp(double amount) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    setState(() => _topUpLoading = true);
    try {
      final url = await WalletService.initializeTopUp(
        customerId: user.id,
        email: user.email ?? '',
        amount: amount,
      );
      if (mounted) Navigator.pop(context);
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      _snack('Complete your payment, then pull to refresh — it can take a few seconds to reflect.');
    } catch (e) {
      _snack('Could not start payment: ${e.toString().replaceFirst('Exception: ', '')}');
    }
    if (mounted) setState(() => _topUpLoading = false);
  }

  void _showTopUpSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              alignment: Alignment.center,
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: EzizaColors.kBorder, borderRadius: BorderRadius.circular(2)))),
          const Text('Top Up Wallet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: EzizaColors.kText)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            decoration: InputDecoration(
              prefixText: '₦ ',
              hintText: 'Amount',
              filled: true,
              fillColor: EzizaColors.kSurface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: EzizaColors.kBorder)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [1000, 2000, 5000, 10000].map((v) => GestureDetector(
            onTap: () => ctrl.text = v.toString(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: EzizaColors.kPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('₦$v', style: const TextStyle(fontSize: 12, color: EzizaColors.kPurpleD, fontWeight: FontWeight.w700)),
            ),
          )).toList()),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _topUpLoading ? null : () {
                final amount = double.tryParse(ctrl.text.trim());
                if (amount == null || amount < 100) {
                  _snack('Enter a valid amount (minimum ₦100).');
                  return;
                }
                _startTopUp(amount);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: EzizaColors.kPurpleD,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _topUpLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue to Payment', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  String _fmt(num n) => '₦${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        title: const Text('Wallet'),
        backgroundColor: EzizaColors.kWhite,
        foregroundColor: EzizaColors.kText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
          : RefreshIndicator(
              color: EzizaColors.kPurpleD,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _balanceCard(),
                  const SizedBox(height: 24),
                  const Text('Transaction History',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: EzizaColors.kText)),
                  const SizedBox(height: 12),
                  if (_transactions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: const Text('No transactions yet.',
                          style: TextStyle(color: EzizaColors.kMuted, fontSize: 13)),
                    )
                  else
                    ..._transactions.map(_transactionCard),
                ],
              ),
            ),
    );
  }

  Widget _balanceCard() => Container(
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF3D1A6E), EzizaColors.kNavy],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.35),
                blurRadius: 16, offset: const Offset(0, 6))]),
        child: Stack(children: [
          Positioned(right: -20, top: -20,
              child: Container(width: 120, height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: EzizaColors.kPurple.withValues(alpha: 0.15)))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Wallet Balance',
                  style: TextStyle(fontSize: 11, color: Colors.white54,
                      fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(_fmt(_balance),
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900,
                      color: EzizaColors.kWhite, letterSpacing: -1.5)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showTopUpSheet,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Top Up', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EzizaColors.kGold,
                    foregroundColor: EzizaColors.kNavy,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _transactionCard(Map<String, dynamic> t) {
    final type = t['type'] as String? ?? '';
    final amount = (t['amount'] as num?)?.toDouble() ?? 0;
    final isCredit = type == 'credit' || type == 'refunded';
    final date = (t['created_at'] as String?)?.substring(0, 10) ?? '';
    final desc = t['description'] as String? ?? type;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EzizaColors.kBorder)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: (isCredit ? EzizaColors.kGold : EzizaColors.kPurple).withValues(alpha: 0.12),
              shape: BoxShape.circle),
          child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 16,
              color: isCredit ? const Color(0xFFD97706) : EzizaColors.kPurpleD),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desc, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: EzizaColors.kText)),
            Text(date, style: const TextStyle(fontSize: 11, color: EzizaColors.kMuted)),
          ]),
        ),
        Text('${isCredit ? '+' : '-'}${_fmt(amount)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                color: isCredit ? const Color(0xFF16A34A) : EzizaColors.kText)),
      ]),
    );
  }
}
