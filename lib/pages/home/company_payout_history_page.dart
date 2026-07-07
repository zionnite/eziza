import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import 'company_earnings_widgets.dart';

class CompanyPayoutHistoryPage extends StatelessWidget {
  const CompanyPayoutHistoryPage({super.key, required this.payouts});

  final List<Map<String, dynamic>> payouts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        title: const Text('Payment History'),
        backgroundColor: EzizaColors.kWhite,
        foregroundColor: EzizaColors.kText,
        elevation: 0,
      ),
      body: payouts.isEmpty
          ? const Center(
              child: Text('No payout requests yet',
                  style: TextStyle(color: EzizaColors.kMuted)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: payouts.length,
              itemBuilder: (context, i) => companyPayoutHistoryCard(payouts[i]),
            ),
    );
  }
}
