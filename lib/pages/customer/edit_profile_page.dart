import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../services/bunny_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _db
          .from('customers')
          .select('full_name, phone, avatar_url')
          .eq('id', uid)
          .maybeSingle();
      _nameCtrl.text = row?['full_name'] as String? ?? '';
      _phoneCtrl.text = row?['phone'] as String? ?? '';
      _avatarUrl = row?['avatar_url'] as String?;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickAvatar() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final image = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
    if (image == null) return;

    setState(() => _uploadingPhoto = true);
    // Timestamped path -- a fixed 'photo' path meant re-uploads reused the
    // same URL, so the CDN edge cache and cached_network_image both kept
    // serving the old photo even after the DB row updated.
    final url = await BunnyService.upload(
        image, 'avatars/$uid/photo_${DateTime.now().millisecondsSinceEpoch}');
    if (url != null) {
      try {
        await _db.from('customers').update({'avatar_url': url}).eq('id', uid);
        if (mounted) setState(() => _avatarUrl = url);
      } catch (_) {
        _snack('Could not save photo. Please try again.');
      }
    } else {
      _snack('Could not upload photo. Please try again.');
    }
    if (mounted) setState(() => _uploadingPhoto = false);
  }

  void _snack(String msg) => Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      backgroundColor: EzizaColors.kPurple,
      colorText: EzizaColors.kWhite,
      snackPosition: SnackPosition.BOTTOM);

  Future<void> _save() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      _snack('Name and phone are required.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _db.from('customers').update({
        'full_name': name,
        'phone': phone,
      }).eq('id', uid);
      // Kept in sync — other parts of the app still read the auth
      // session's user_metadata directly (e.g. rating attribution).
      await _db.auth.updateUser(UserAttributes(data: {'full_name': name, 'phone': phone}));
      if (!mounted) return;
      Get.back();
      _snack('Profile updated.');
    } catch (_) {
      _snack('Could not update profile. Please try again.');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: EzizaColors.kWhite,
        foregroundColor: EzizaColors.kText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Center(
                  child: Stack(children: [
                    Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _avatarUrl == null
                            ? const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD])
                            : null,
                        image: _avatarUrl != null
                            ? DecorationImage(
                                image: CachedNetworkImageProvider(_avatarUrl!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: _avatarUrl == null
                          ? Center(
                              child: Text(
                                _nameCtrl.text.trim().isEmpty
                                    ? '?'
                                    : _nameCtrl.text.trim()[0].toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0, bottom: 0,
                      child: GestureDetector(
                        onTap: _uploadingPhoto ? null : _pickAvatar,
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                              color: EzizaColors.kGold,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2)),
                          child: _uploadingPhoto
                              ? const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: EzizaColors.kNavy))
                              : const Icon(Icons.camera_alt_rounded, size: 16, color: EzizaColors.kNavy),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: EzizaColors.kWhite,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: EzizaColors.kBorder),
                      boxShadow: [
                        BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.05),
                            blurRadius: 10, offset: const Offset(0, 4))
                      ]),
                  child: Column(children: [
                    _field(_nameCtrl, 'Full Name', Icons.person_outline_rounded),
                    const SizedBox(height: 14),
                    _field(_phoneCtrl, 'Phone Number', Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ]),
                  ]),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.3),
                                blurRadius: 10, offset: const Offset(0, 4))
                          ]),
                      child: _saving
                          ? const Center(
                              child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                          : const Text('Save Changes',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
