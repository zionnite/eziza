import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../services/bunny_service.dart';

/// Company's first-ever post-registration profile editor — mirrors the
/// rider's ProfilePage structure (Personal/Company Info), adapted to the
/// companies table's own columns. Bank details live in their own detached
/// BankAccountPage, not here.
class CompanyProfilePage extends StatefulWidget {
  const CompanyProfilePage({super.key});

  @override
  State<CompanyProfilePage> createState() => _CompanyProfilePageState();
}

class _CompanyProfilePageState extends State<CompanyProfilePage> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _contactPersonCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cacCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  String? _companyId;
  String? _email;
  String? _avatarUrl;
  String? _status;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactPersonCtrl.dispose();
    _phoneCtrl.dispose();
    _cacCtrl.dispose();
    _stateCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _db.from('companies').select().eq('auth_user_id', uid).single();

      _companyId = row['id'] as String;
      _email = row['email'] as String?;
      _avatarUrl = row['avatar_url'] as String?;
      _status = row['status'] as String? ?? 'pending';
      _nameCtrl.text = row['name'] as String? ?? '';
      _contactPersonCtrl.text = row['contact_person'] as String? ?? '';
      _phoneCtrl.text = row['phone'] as String? ?? '';
      _cacCtrl.text = row['cac_number'] as String? ?? '';
      _stateCtrl.text = row['state'] as String? ?? '';
      _cityCtrl.text = row['city'] as String? ?? '';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickAvatar() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || _companyId == null) return;
    final image = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
    if (image == null) return;

    setState(() => _uploadingPhoto = true);
    final url = await BunnyService.upload(image, 'avatars/$uid/photo');
    if (url != null) {
      try {
        await _db.from('companies').update({'avatar_url': url}).eq('id', _companyId!);
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
    if (!(_formKey.currentState?.validate() ?? false) || _companyId == null) return;
    setState(() => _saving = true);
    try {
      await _db.from('companies').update({
        'name': _nameCtrl.text.trim(),
        'contact_person': _contactPersonCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'cac_number': _cacCtrl.text.trim().isEmpty ? null : _cacCtrl.text.trim(),
        'state': _stateCtrl.text.trim(),
        'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      }).eq('id', _companyId!);
      if (!mounted) return;
      _snack('Profile updated.');
    } catch (_) {
      _snack('Could not update profile. Please try again.');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final initials = _nameCtrl.text.trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final (Color statusColor, String statusLabel) = switch (_status) {
      'approved' => (const Color(0xFF4ADE80), 'Approved'),
      'rejected' => (EzizaColors.kError, 'Rejected'),
      'suspended' => (Colors.orange, 'Suspended'),
      _ => (EzizaColors.kGold, 'Pending'),
    };

    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EzizaColors.kPurpleD))
          : SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _hero(initials, statusColor, statusLabel),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _sectionLabel('Company Info'),
                      const SizedBox(height: 12),
                      _field(_nameCtrl, 'Company Name', Icons.business_rounded,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),
                      const SizedBox(height: 12),
                      _field(_contactPersonCtrl, 'Contact Person', Icons.person_outline_rounded),
                      const SizedBox(height: 12),
                      _field(_phoneCtrl, 'Phone Number', Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),
                      const SizedBox(height: 12),
                      _readOnlyField('Email', _email ?? '', Icons.alternate_email_rounded),
                      const SizedBox(height: 12),
                      _field(_cacCtrl, 'CAC Number (optional)', Icons.badge_outlined),
                      const SizedBox(height: 24),
                      _sectionLabel('Location'),
                      const SizedBox(height: 12),
                      _field(_stateCtrl, 'State', Icons.map_outlined,
                          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),
                      const SizedBox(height: 12),
                      _field(_cityCtrl, 'City (optional)', Icons.location_city_outlined),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [EzizaColors.kPurpleD, EzizaColors.kPurple]),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: EzizaColors.kPurple.withValues(alpha: 0.3),
                                    blurRadius: 10, offset: const Offset(0, 4))
                              ]),
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            child: _saving
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Save Changes',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _hero(String initials, Color statusColor, String statusLabel) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
            boxShadow: [
              BoxShadow(color: Color(0x446C3483), blurRadius: 16, offset: Offset(0, 6))
            ]),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                  ),
                ),
                const Spacer(),
                const Text('Company Profile',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                const SizedBox(width: 38),
              ]),
              const SizedBox(height: 22),
              Row(children: [
                Stack(children: [
                  Container(
                    width: 62, height: 62,
                    decoration: BoxDecoration(
                      gradient: _avatarUrl == null
                          ? const LinearGradient(colors: [EzizaColors.kPurple, EzizaColors.kPurpleD])
                          : null,
                      shape: BoxShape.circle,
                      image: _avatarUrl != null
                          ? DecorationImage(image: CachedNetworkImageProvider(_avatarUrl!), fit: BoxFit.cover)
                          : null,
                      boxShadow: [
                        BoxShadow(color: EzizaColors.kPurpleD.withValues(alpha: 0.4),
                            blurRadius: 12, offset: const Offset(0, 4))
                      ],
                    ),
                    child: _avatarUrl == null
                        ? Center(
                            child: Text(initials.isEmpty ? '?' : initials,
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)))
                        : null,
                  ),
                  Positioned(
                    right: -2, bottom: -2,
                    child: GestureDetector(
                      onTap: _uploadingPhoto ? null : _pickAvatar,
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                            color: EzizaColors.kGold, shape: BoxShape.circle,
                            border: Border.all(color: EzizaColors.kNavy, width: 2)),
                        child: _uploadingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(4),
                                child: CircularProgressIndicator(strokeWidth: 2, color: EzizaColors.kNavy))
                            : const Icon(Icons.camera_alt_rounded, size: 12, color: EzizaColors.kNavy),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_nameCtrl.text.isEmpty ? 'Company' : _nameCtrl.text,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4))),
                      child: Text(statusLabel,
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ]),
            ]),
          ),
        ),
      );

  Widget _sectionLabel(String label) =>
      Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: EzizaColors.kText));

  Widget _readOnlyField(String label, String value, IconData icon) => TextFormField(
        initialValue: value,
        enabled: false,
        style: const TextStyle(color: EzizaColors.kMuted),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: EzizaColors.kMuted),
          prefixIcon: Icon(icon, color: EzizaColors.kMuted, size: 20),
          filled: true,
          fillColor: EzizaColors.kBorder.withValues(alpha: 0.3),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );

  TextFormField _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
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
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: EzizaColors.kError)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
