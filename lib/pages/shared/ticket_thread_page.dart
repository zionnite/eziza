import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../services/bunny_service.dart';
import 'support_tickets_page.dart';

/// Ported from ZeeFashion's ticket_thread_page.dart. Image attachments go
/// through BunnyService.upload() (Eziza's own Bunny zone) instead of the
/// raw HTTP PUT + hardcoded key ZeeFashion's version uses.
class TicketThreadPage extends StatefulWidget {
  final Map<String, dynamic> ticket;
  const TicketThreadPage({super.key, required this.ticket});

  @override
  State<TicketThreadPage> createState() => _TicketThreadPageState();
}

class _TicketThreadPageState extends State<TicketThreadPage> {
  final _db = Supabase.instance.client;
  String get _uid => _db.auth.currentUser?.id ?? '';

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  RealtimeChannel? _channel;

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _uploadingImg = false;
  late String _status;

  @override
  void initState() {
    super.initState();
    _status = widget.ticket['status'] as String? ?? 'open';
    _loadMessages();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final data = await _db
        .from('support_messages')
        .select()
        .eq('ticket_id', widget.ticket['id'])
        .order('created_at', ascending: true);
    if (!mounted) return;
    setState(() {
      _messages = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
    _scrollToBottom();
  }

  void _subscribe() {
    final ticketId = widget.ticket['id'] as int;
    _channel = _db
        .channel('support_ticket_$ticketId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ticket_id',
            value: ticketId,
          ),
          callback: (payload) {
            final msg = Map<String, dynamic>.from(payload.newRecord);
            if (!mounted) return;
            if (!_messages.any((m) => m['id'] == msg['id'])) {
              setState(() => _messages.add(msg));
              _scrollToBottom();
            }
          },
        )
        .subscribe();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send({String? imageUrl}) async {
    final text = _msgCtrl.text.trim();
    if ((text.isEmpty && imageUrl == null) || _status == 'closed') return;
    setState(() => _sending = true);
    _msgCtrl.clear();
    try {
      await _db.from('support_messages').insert({
        'ticket_id': widget.ticket['id'],
        'sender_id': _uid,
        'sender_type': 'user',
        'message': text.isEmpty ? '📷 Image' : text,
        'image_url': ?imageUrl,
      });
    } catch (_) {
      _msgCtrl.text = text;
      if (mounted) {
        Get.snackbar('Error', 'Could not send message.',
            backgroundColor: EzizaColors.kError, colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    final file = await _picker.pickImage(source: source, imageQuality: 75, maxWidth: 1200);
    if (file == null) return;

    setState(() => _uploadingImg = true);
    try {
      final url = await BunnyService.upload(file, 'support/$_uid/${DateTime.now().millisecondsSinceEpoch}');
      if (url == null) throw Exception('upload failed');
      await _send(imageUrl: url);
    } catch (_) {
      if (mounted) {
        Get.snackbar('Upload Failed', 'Could not upload image.',
            backgroundColor: EzizaColors.kError, colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _uploadingImg = false);
    }
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: EzizaColors.kWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: EzizaColors.kBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: EzizaColors.kPurple),
            title: const Text('Choose from Gallery', style: TextStyle(color: EzizaColors.kText, fontSize: 14)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: EzizaColors.kPurple),
            title: const Text('Take a Photo', style: TextStyle(color: EzizaColors.kText, fontSize: 14)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _fmtTime(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isClosed = _status == 'closed' || _status == 'resolved';
    final color = kStatusColors[_status] ?? EzizaColors.kMuted;
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        backgroundColor: EzizaColors.kWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: EzizaColors.kText),
          onPressed: () => Get.back(),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('#${widget.ticket['id']} · ${widget.ticket['subject']}',
              style: const TextStyle(color: EzizaColors.kText, fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(statusLabel(_status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _bubble(_messages[i]),
                ),
        ),
        if (_uploadingImg)
          Container(
            color: EzizaColors.kWhite,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: EzizaColors.kPurple, strokeWidth: 2)),
              const SizedBox(width: 10),
              const Text('Uploading image…', style: TextStyle(color: EzizaColors.kMuted, fontSize: 13)),
            ]),
          ),
        if (isClosed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: EzizaColors.kWhite, border: Border(top: BorderSide(color: EzizaColors.kBorder))),
            child: Text(
              _status == 'resolved'
                  ? '✅ This ticket has been resolved. Open a new ticket if you need further help.'
                  : 'This ticket is closed.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: EzizaColors.kMuted, fontSize: 13),
            ),
          )
        else
          _inputBar(),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> msg) {
    final isMe = msg['sender_type'] == 'user';
    final imgUrl = msg['image_url'] as String?;
    final hasText = (msg['message'] as String? ?? '').isNotEmpty && msg['message'] != '📷 Image';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? EzizaColors.kPurple : EzizaColors.kWhite,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 12),
          ),
          border: isMe ? null : Border.all(color: EzizaColors.kBorder),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        padding: imgUrl != null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!isMe)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text('Support Team', style: TextStyle(color: EzizaColors.kPurple, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          if (imgUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imgUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(height: 160, color: EzizaColors.kSurface,
                        child: const Center(child: CircularProgressIndicator(color: EzizaColors.kPurple, strokeWidth: 2))),
                errorBuilder: (_, _, _) => Container(
                  height: 80, color: EzizaColors.kSurface,
                  child: const Center(child: Icon(Icons.broken_image_outlined, color: EzizaColors.kMuted)),
                ),
              ),
            ),
          if (hasText)
            Padding(
              padding: EdgeInsets.fromLTRB(14, imgUrl != null ? 8 : 0, 14, 0),
              child: Text(msg['message'] ?? '',
                  style: TextStyle(color: isMe ? Colors.white : EzizaColors.kText, fontSize: 14, height: 1.45)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Text(_fmtTime(msg['created_at'] ?? ''),
                style: TextStyle(color: isMe ? Colors.white54 : EzizaColors.kMuted, fontSize: 10)),
          ),
        ]),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.only(left: 16, right: 12, top: 10, bottom: MediaQuery.of(context).viewInsets.bottom + 10),
      decoration: const BoxDecoration(color: EzizaColors.kWhite, border: Border(top: BorderSide(color: EzizaColors.kBorder))),
      child: Row(children: [
        GestureDetector(
          onTap: _uploadingImg ? null : _pickImage,
          child: Container(
            width: 40, height: 40,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: EzizaColors.kSurface, borderRadius: BorderRadius.circular(20), border: Border.all(color: EzizaColors.kBorder)),
            child: Icon(Icons.image_outlined, color: _uploadingImg ? EzizaColors.kMuted : EzizaColors.kPurple, size: 20),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            style: const TextStyle(color: EzizaColors.kText, fontSize: 14),
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Type a message…',
              hintStyle: const TextStyle(color: EzizaColors.kMuted, fontSize: 13),
              filled: true, fillColor: EzizaColors.kSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: EzizaColors.kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: EzizaColors.kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: EzizaColors.kPurple)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: (_sending || _uploadingImg) ? null : _send,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44, height: 44,
            decoration: BoxDecoration(color: (_sending || _uploadingImg) ? EzizaColors.kMuted : EzizaColors.kPurple, shape: BoxShape.circle),
            child: _sending
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
