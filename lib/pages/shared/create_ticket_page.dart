import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import 'support_tickets_page.dart';

/// Ported from ZeeFashion's create_ticket_page.dart, shared across all 3
/// Eziza roles (see support_tickets_page.dart's note on why that's safe).
class CreateTicketPage extends StatefulWidget {
  const CreateTicketPage({super.key});

  @override
  State<CreateTicketPage> createState() => _CreateTicketPageState();
}

class _CreateTicketPageState extends State<CreateTicketPage> {
  final _db = Supabase.instance.client;
  String get _uid => _db.auth.currentUser?.id ?? '';

  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _category = 'delivery_issue';
  bool _submitting = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final ticket = await _db.from('support_tickets').insert({
        'user_id':  _uid,
        'subject':  _subjectCtrl.text.trim(),
        'category': _category,
      }).select().single();

      await _db.from('support_messages').insert({
        'ticket_id':   ticket['id'],
        'sender_id':   _uid,
        'sender_type': 'user',
        'message':     _messageCtrl.text.trim(),
      });

      if (!mounted) return;
      Get.back(result: true);
      Get.snackbar('Ticket Created', 'Our support team will respond shortly.',
          backgroundColor: EzizaColors.kPurpleD, colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(16));
    } catch (_) {
      Get.snackbar('Error', 'Could not submit ticket. Please try again.',
          backgroundColor: EzizaColors.kError, colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(16));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kWhite,
      appBar: AppBar(
        backgroundColor: EzizaColors.kWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: EzizaColors.kText),
          onPressed: () => Get.back(),
        ),
        title: const Text('New Support Ticket',
            style: TextStyle(color: EzizaColors.kText, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _label('Category'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: EzizaColors.kBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
                  dropdownColor: EzizaColors.kWhite,
                  onChanged: (v) => setState(() => _category = v!),
                  items: kCategoryLabels.entries
                      .map((c) => DropdownMenuItem(value: c.key, child: Text(c.value)))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label('Subject'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _subjectCtrl,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
              decoration: _inputDec('Brief description of your issue'),
            ),
            const SizedBox(height: 16),
            _label('Message'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _messageCtrl,
              validator: (v) => v == null || v.trim().length < 10
                  ? 'Please provide more detail (at least 10 characters)'
                  : null,
              style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
              maxLines: 6,
              decoration: _inputDec('Describe your issue in detail…'),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EzizaColors.kPurple,
                  disabledBackgroundColor: EzizaColors.kMuted,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Submit Ticket',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) =>
      Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: EzizaColors.kText));

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: EzizaColors.kMuted, fontSize: 13),
        filled: true,
        fillColor: EzizaColors.kSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EzizaColors.kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EzizaColors.kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EzizaColors.kPurple, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EzizaColors.kError)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: EzizaColors.kError)),
      );
}
