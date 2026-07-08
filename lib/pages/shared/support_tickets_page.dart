import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import 'create_ticket_page.dart';
import 'ticket_thread_page.dart';

const kCategoryLabels = {
  'delivery_issue':  'Delivery Issue',
  'payment_issue':   'Payment Issue',
  'refund_issue':    'Refund Issue',
  'account_issue':   'Account Issue',
  'rider_issue':     'Rider Issue',
  'technical_issue': 'Technical Issue',
  'other':           'Other',
};

const kStatusColors = {
  'open':        Color(0xFFF59E0B),
  'in_progress': Color(0xFF3B82F6),
  'resolved':    Color(0xFF22C55E),
  'closed':      EzizaColors.kMuted,
};

String statusLabel(String s) => s
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// One shared page for all 3 roles (rider/company/customer) -- Eziza has no
/// unified profiles table, so support_tickets.user_id is just the auth uid
/// and "who this belongs to" doesn't need to be role-aware client-side.
/// Ported from ZeeFashion's support_tickets_page.dart.
class SupportTicketsPage extends StatefulWidget {
  const SupportTicketsPage({super.key});

  @override
  State<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends State<SupportTicketsPage> {
  final _db = Supabase.instance.client;
  String get _uid => _db.auth.currentUser?.id ?? '';

  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _db
          .from('support_tickets')
          .select()
          .eq('user_id', _uid)
          .order('updated_at', ascending: false);
      if (mounted) {
        setState(() {
          _tickets = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Column(children: [
        _hero(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
              : _tickets.isEmpty
                  ? _empty()
                  : RefreshIndicator(
                      color: EzizaColors.kPurpleD,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _tickets.length,
                        itemBuilder: (_, i) => _ticketCard(_tickets[i]),
                      ),
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: EzizaColors.kPurple,
        onPressed: () async {
          final created = await Get.to(() => const CreateTicketPage());
          if (created == true) _load();
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Ticket', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                  Text('Support Tickets',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 3),
                  Text('We usually reply within a few hours',
                      style: TextStyle(fontSize: 12, color: Colors.white60)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 20),
              ),
            ]),
          ),
        ),
      );

  Widget _empty() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.support_agent_outlined, size: 64, color: EzizaColors.kMuted),
          const SizedBox(height: 16),
          const Text('No support tickets yet',
              style: TextStyle(fontWeight: FontWeight.w600, color: EzizaColors.kText, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Tap + to open a new ticket', style: TextStyle(color: EzizaColors.kMuted, fontSize: 13)),
        ]),
      );

  Widget _ticketCard(Map<String, dynamic> t) {
    final status = t['status'] as String? ?? 'open';
    final color = kStatusColors[status] ?? EzizaColors.kMuted;
    return GestureDetector(
      onTap: () async {
        await Get.to(() => TicketThreadPage(ticket: t));
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EzizaColors.kBorder),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('#${t['id']} · ${t['subject']}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: EzizaColors.kText),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(statusLabel(status), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(kCategoryLabels[t['category']] ?? t['category'] ?? '',
                style: const TextStyle(color: EzizaColors.kMuted, fontSize: 12)),
            Text(_fmtDate(t['updated_at'] ?? t['created_at'] ?? ''),
                style: const TextStyle(color: EzizaColors.kMuted, fontSize: 12)),
          ]),
        ]),
      ),
    );
  }
}
