import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../widgets/premium_card.dart';
import 'earnings_widgets.dart';

/// Lets a company see who rated one of their riders — attribution matters
/// specifically so a bad rating can be traced back to the customer involved.
class CompanyRiderRatingsPage extends StatefulWidget {
  const CompanyRiderRatingsPage({
    super.key,
    required this.riderId,
    required this.riderName,
  });

  final String riderId; // riders.id
  final String riderName;

  @override
  State<CompanyRiderRatingsPage> createState() =>
      _CompanyRiderRatingsPageState();
}

class _CompanyRiderRatingsPageState extends State<CompanyRiderRatingsPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _ratings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _db
          .from('delivery_ratings')
          .select()
          .eq('ratee_id', widget.riderId)
          .eq('ratee_role', 'rider')
          .order('created_at', ascending: false);
      _ratings = List<Map<String, dynamic>>.from(res);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        title: Text("${widget.riderName}'s Ratings"),
        backgroundColor: EzizaColors.kWhite,
        foregroundColor: EzizaColors.kText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
          : RefreshIndicator(
              color: EzizaColors.kPurpleD,
              onRefresh: _load,
              child: _ratings.isEmpty
                  ? earningsEmptyState(
                      Icons.star_outline_rounded,
                      'No Ratings Yet',
                      'Ratings from senders and receivers will appear here.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _ratings.length,
                      itemBuilder: (_, i) => _ratingCard(_ratings[i]),
                    ),
            ),
    );
  }

  Widget _ratingCard(Map<String, dynamic> r) {
    final rating  = (r['rating'] as num?)?.toInt() ?? 0;
    final role    = r['rater_role'] as String? ?? '';
    final name    = (r['rater_name'] as String?)?.trim();
    final comment = r['comment'] as String?;
    final date    = r['created_at'] as String? ?? '';
    final dateLabel = date.length >= 10 ? date.substring(0, 10) : date;
    final roleLabel = role == 'sender' ? 'Sender' : 'Receiver';

    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  (name == null || name.isEmpty) ? 'Anonymous' : name,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: EzizaColors.kText)),
            ),
            StatusPill(label: roleLabel, color: EzizaColors.kPurpleD),
          ]),
          const SizedBox(height: 8),
          Row(children: List.generate(
              5,
              (i) => Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: EzizaColors.kGold,
                  size: 18))),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment,
                style: const TextStyle(fontSize: 13, color: EzizaColors.kText)),
          ],
          const SizedBox(height: 6),
          Text(dateLabel,
              style: const TextStyle(fontSize: 11, color: EzizaColors.kMuted)),
        ],
      ),
    );
  }
}
