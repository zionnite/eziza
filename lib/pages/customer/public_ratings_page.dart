import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../widgets/premium_card.dart';
import '../home/earnings_widgets.dart';

/// Lets a customer see a rider's or company's rating history before
/// accepting their bid. Anonymised (no rater name) via the get_public_ratings
/// RPC -- unlike CompanyRiderRatingsPage, which shows full rater attribution
/// to the rider's own employer for dispute-tracing, this is a public-facing
/// reputation view any customer can open from the bid list.
class PublicRatingsPage extends StatefulWidget {
  const PublicRatingsPage({
    super.key,
    required this.rateeType, // 'rider' | 'company'
    required this.rateeId,
    required this.name,
    required this.ratingAvg,
    required this.ratingCount,
  });

  final String rateeType;
  final String rateeId;
  final String name;
  final double ratingAvg;
  final int ratingCount;

  @override
  State<PublicRatingsPage> createState() => _PublicRatingsPageState();
}

class _PublicRatingsPageState extends State<PublicRatingsPage> {
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
      final res = await _db.rpc('get_public_ratings', params: {
        'p_ratee_type': widget.rateeType,
        'p_ratee_id': widget.rateeId,
      });
      _ratings = List<Map<String, dynamic>>.from(res as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        title: Text("${widget.name}'s Rating"),
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 20),
                  if (_ratings.isEmpty)
                    earningsEmptyState(
                        Icons.star_outline_rounded,
                        'No Ratings Yet',
                        '${widget.name} hasn\'t received any ratings yet.')
                  else
                    ..._ratings.map(_reviewCard),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard() => PremiumCard(
        glow: EzizaColors.kGold,
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.ratingAvg > 0 ? widget.ratingAvg.toStringAsFixed(1) : '—',
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: EzizaColors.kText)),
            const SizedBox(height: 4),
            Row(children: List.generate(
                5,
                (i) => Icon(
                    i < widget.ratingAvg.round()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: EzizaColors.kGold,
                    size: 16))),
          ]),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
                '${widget.ratingCount} rating${widget.ratingCount == 1 ? '' : 's'}',
                style:
                    const TextStyle(fontSize: 13, color: EzizaColors.kMuted)),
          ),
        ]),
      );

  Widget _reviewCard(Map<String, dynamic> r) {
    final rating = (r['rating'] as num?)?.toInt() ?? 0;
    final role = r['rater_role'] as String? ?? '';
    final comment = r['comment'] as String?;
    final date = r['created_at'] as String? ?? '';
    final dateLabel = date.length >= 10 ? date.substring(0, 10) : date;
    final roleLabel = role == 'sender' ? 'Sender' : 'Receiver';

    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Row(children: List.generate(
                5,
                (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: EzizaColors.kGold,
                    size: 16))),
            const Spacer(),
            StatusPill(label: roleLabel, color: EzizaColors.kPurpleD),
          ]),
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
