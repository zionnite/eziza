import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import 'company_earnings_widgets.dart';

class CompanyEarningsHistoryPage extends StatelessWidget {
  const CompanyEarningsHistoryPage({super.key, required this.deliveries});

  final List<Map<String, dynamic>> deliveries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        title: const Text('Recent Earnings'),
        backgroundColor: EzizaColors.kWhite,
        foregroundColor: EzizaColors.kText,
        elevation: 0,
      ),
      body: deliveries.isEmpty
          ? const Center(
              child: Text('No confirmed deliveries yet',
                  style: TextStyle(color: EzizaColors.kMuted)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: deliveries.length,
              itemBuilder: (context, i) =>
                  companyEarningsHistoryCard(deliveries[i]),
            ),
    );
  }
}
