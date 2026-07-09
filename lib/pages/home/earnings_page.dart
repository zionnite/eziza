import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../models/delivery.dart';
import '../../models/payout_request.dart';
import '../../services/supabase_service.dart';
import '../../utils/currency.dart';
import '../../widgets/premium_card.dart';

class EarningsPage extends StatefulWidget {
  const EarningsPage({super.key});

  @override
  State<EarningsPage> createState() => _EarningsPageState();
}

class _EarningsPageState extends State<EarningsPage> {
  final _auth = Get.find<AuthController>();

  List<Delivery>      _deliveries = [];
  List<PayoutRequest> _payouts    = [];
  bool _loading = true;

  final _naira = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
  final _dateFmt = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rider = _auth.rider.value;
    if (rider == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SupabaseService.getCompletedDeliveries(rider.id),
        SupabaseService.getPayoutRequests(rider.id),
      ]);
      if (!mounted) return;
      setState(() {
        _deliveries = results[0].map((r) => Delivery.fromJson(r)).toList();
        _payouts    = results[1].map((r) => PayoutRequest.fromJson(r)).toList();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Payout request sheet ──────────────────────────────────

  void _showPayoutSheet() {
    final rider = _auth.rider.value!;
    final balance = rider.walletBalance;

    if (balance <= 0) {
      Get.snackbar(
        'No balance', 'Your wallet balance is ₦0.',
        backgroundColor: EzizaColors.kMuted,
        colorText: EzizaColors.kWhite,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
      );
      return;
    }

    final amountCtrl  = TextEditingController(text: formatAmount(balance));
    final bankCtrl    = TextEditingController(text: rider.bankName ?? '');
    final accNumCtrl  = TextEditingController(text: rider.accountNumber ?? '');
    final accNameCtrl = TextEditingController(text: rider.accountName ?? '');
    final formKey     = GlobalKey<FormState>();
    var submitting    = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: EzizaColors.kBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Request Payout',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: EzizaColors.kText)),
                const SizedBox(height: 4),
                Text('Available: ${_naira.format(balance)}',
                    style: const TextStyle(
                        color: EzizaColors.kMuted, fontSize: 13)),
                const SizedBox(height: 20),
                _sheetField(
                  controller: amountCtrl,
                  label: 'Amount (₦)',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    ThousandsSeparatorInputFormatter(),
                  ],
                  validator: (v) {
                    final amt = parseFormattedAmount(v?.trim() ?? '');
                    if (amt == null || amt <= 0) return 'Enter a valid amount';
                    if (amt > balance) {
                      return 'Cannot exceed balance (${_naira.format(balance)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _sheetField(
                  controller: bankCtrl,
                  label: 'Bank Name',
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                _sheetField(
                  controller: accNumCtrl,
                  label: 'Account Number',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (v) {
                    if ((v?.trim().length ?? 0) != 10) {
                      return 'Must be 10 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _sheetField(
                  controller: accNameCtrl,
                  label: 'Account Name',
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [EzizaColors.kPurpleD, EzizaColors.kPurple]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: submitting
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setSheet(() => submitting = true);
                              final result =
                                  await SupabaseService.requestPayout(
                                riderId:       rider.id,
                                amount:        parseFormattedAmount(amountCtrl.text.trim())!,
                                bankName:      bankCtrl.text.trim(),
                                accountNumber: accNumCtrl.text.trim(),
                                accountName:   accNameCtrl.text.trim(),
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (result == 'true') {
                                Get.snackbar(
                                  'Request submitted',
                                  'Your payout request is being processed.',
                                  backgroundColor: EzizaColors.kSuccess,
                                  colorText: EzizaColors.kWhite,
                                  snackPosition: SnackPosition.BOTTOM,
                                  margin: const EdgeInsets.all(16),
                                );
                                _load();
                              } else {
                                Get.snackbar(
                                  'Error', result,
                                  backgroundColor: EzizaColors.kError,
                                  colorText: EzizaColors.kWhite,
                                  snackPosition: SnackPosition.BOTTOM,
                                  margin: const EdgeInsets.all(16),
                                );
                              }
                            },
                      child: submitting
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: EzizaColors.kWhite, strokeWidth: 2))
                          : const Text('Submit Request',
                              style: TextStyle(
                                  color: EzizaColors.kWhite,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rider = _auth.rider.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurple))
          : RefreshIndicator(
              onRefresh: _load,
              color: EzizaColors.kPurple,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildBalanceCard(rider?.walletBalance ?? 0),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'Completed Deliveries',
                    count: _deliveries.length,
                    child: _deliveries.isEmpty
                        ? _emptyState(
                            Icons.local_shipping_outlined,
                            'No completed deliveries yet')
                        : Column(
                            children: _deliveries
                                .map((d) => _DeliveryItem(
                                      delivery: d,
                                      naira: _naira,
                                      dateFmt: _dateFmt,
                                    ))
                                .toList(),
                          ),
                  ),
                  if (_payouts.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSection(
                      title: 'Payout History',
                      count: _payouts.length,
                      child: Column(
                        children: _payouts
                            .map((p) => _PayoutItem(
                                  payout: p,
                                  naira: _naira,
                                  dateFmt: _dateFmt,
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard(double balance) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [EzizaColors.kPurpleD, EzizaColors.kPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: EzizaColors.kPurpleD.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 16),
            spreadRadius: -8,
          ),
          BoxShadow(
            color: EzizaColors.kNavy.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(children: [
          Positioned(right: -30, top: -30,
              child: Container(width: 140, height: 140,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08)))),
          Positioned(left: -30, bottom: -40,
              child: Container(width: 130, height: 130,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: EzizaColors.kGold.withValues(alpha: 0.08)))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wallet Balance',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Text(
                  _naira.format(balance),
                  style: const TextStyle(
                    color: EzizaColors.kWhite,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 20),
                PremiumButton(
                  label: 'Request Payout',
                  icon: Icons.account_balance_outlined,
                  colors: const [EzizaColors.kGold, Color(0xFFD97706)],
                  onTap: _showPayoutSheet,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required int count,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: EzizaColors.kText)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: EzizaColors.kSurface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: EzizaColors.kBorder),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EzizaColors.kMuted)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _emptyState(IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 48, color: EzizaColors.kBorder),
              const SizedBox(height: 12),
              Text(label,
                  style: const TextStyle(color: EzizaColors.kMuted)),
            ],
          ),
        ),
      );

  TextFormField _sheetField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: EzizaColors.kMuted),
          filled: true,
          fillColor: EzizaColors.kSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: EzizaColors.kBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: EzizaColors.kBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: EzizaColors.kPurple, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}

// ── Completed delivery row ────────────────────────────────────

class _DeliveryItem extends StatelessWidget {
  final Delivery delivery;
  final NumberFormat naira;
  final DateFormat dateFmt;
  const _DeliveryItem({
    required this.delivery,
    required this.naira,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    final earned = delivery.agreedPrice ?? 0;
    final fee    = delivery.platformFee ?? 0;
    final net    = earned - fee;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EzizaColors.kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EzizaColors.kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: EzizaColors.kSuccess.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: EzizaColors.kSuccess, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  delivery.externalOrderId,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: EzizaColors.kText),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_shorten(delivery.pickupAddress)} → ${_shorten(delivery.deliveryAddress)}',
                  style: const TextStyle(
                      color: EzizaColors.kMuted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (delivery.confirmedAt != null)
                  Text(
                    dateFmt.format(delivery.confirmedAt!),
                    style: const TextStyle(
                        color: EzizaColors.kMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(naira.format(net),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: EzizaColors.kText)),
              if (fee > 0)
                Text('–${naira.format(fee)} fee',
                    style: const TextStyle(
                        color: EzizaColors.kMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  String _shorten(String address) {
    final parts = address.split(',');
    return parts.first.trim();
  }
}

// ── Payout request row ────────────────────────────────────────

class _PayoutItem extends StatelessWidget {
  final PayoutRequest payout;
  final NumberFormat  naira;
  final DateFormat    dateFmt;
  const _PayoutItem({
    required this.payout,
    required this.naira,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (payout.status) {
      'paid'     => (EzizaColors.kSuccess, Icons.check_circle_rounded, 'Paid'),
      'rejected' => (EzizaColors.kError, Icons.cancel_rounded, 'Rejected'),
      _          => (EzizaColors.kGold, Icons.hourglass_top_rounded, 'Pending'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EzizaColors.kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EzizaColors.kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payout Request',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: EzizaColors.kText)),
                Text(dateFmt.format(payout.createdAt),
                    style: const TextStyle(
                        color: EzizaColors.kMuted, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(naira.format(payout.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: EzizaColors.kText)),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
