import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import 'customer_delivery_detail_page.dart';
import 'location_picker_sheet.dart';

// Fixed tenant UUID for direct customer orders (matches migration seed)
const _kDirectTenantId = '00000000-0000-0000-0000-000000000001';

class SendPackagePage extends StatefulWidget {
  const SendPackagePage({super.key});

  @override
  State<SendPackagePage> createState() => _SendPackagePageState();
}

class _SendPackagePageState extends State<SendPackagePage>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;

  // Map-picked locations
  String? _pickupAddress;
  double? _pickupLat;
  double? _pickupLng;
  String? _pickupState;

  String? _dropoffAddress;
  double? _dropoffLat;
  double? _dropoffLng;

  final _pickupContactCtrl = TextEditingController();
  final _pickupPhoneCtrl   = TextEditingController();

  final _deliveryContactCtrl = TextEditingController();
  final _deliveryPhoneCtrl   = TextEditingController();

  final _descCtrl  = TextEditingController();
  final _valueCtrl = TextEditingController();

  bool _submitting = false;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    // Pre-fill sender's own contact from metadata
    final user = _db.auth.currentUser;
    _pickupContactCtrl.text =
        user?.userMetadata?['full_name'] as String? ?? '';
    _pickupPhoneCtrl.text =
        user?.userMetadata?['phone'] as String? ?? '';
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _pickupContactCtrl.dispose();
    _pickupPhoneCtrl.dispose();
    _deliveryContactCtrl.dispose();
    _deliveryPhoneCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPickup() async {
    final result = await LocationPickerSheet.pick(
      title: 'Pickup Location',
      subtitle: 'Where should the rider collect the package?',
    );
    if (result != null && mounted) {
      setState(() {
        _pickupAddress = result.address;
        _pickupLat     = result.lat;
        _pickupLng     = result.lng;
        _pickupState   = result.state.isEmpty ? null : result.state;
      });
    }
  }

  Future<void> _pickDropoff() async {
    final result = await LocationPickerSheet.pick(
      title: 'Dropoff Location',
      subtitle: 'Where should the package be delivered?',
    );
    if (result != null && mounted) {
      setState(() {
        _dropoffAddress = result.address;
        _dropoffLat     = result.lat;
        _dropoffLng     = result.lng;
      });
    }
  }

  Future<void> _submit() async {
    if (_pickupAddress == null || _pickupLat == null) {
      _snack('Pick a pickup location on the map.');
      return;
    }
    if (_dropoffAddress == null || _dropoffLat == null) {
      _snack('Pick a dropoff location on the map.');
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      _snack('Describe the package.');
      return;
    }

    final user = _db.auth.currentUser;
    if (user == null) {
      _snack('Not logged in.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final value = double.tryParse(_valueCtrl.text.trim());
      final now   = DateTime.now().toUtc();
      final extId = '${user.id.substring(0, 8)}-${now.millisecondsSinceEpoch}';

      final result = await _db.from('deliveries').insert({
        'tenant_id':            _kDirectTenantId,
        'external_order_id':    extId,
        'customer_id':          user.id,
        'pickup_address':       _pickupAddress,
        'pickup_lat':           _pickupLat,
        'pickup_lng':           _pickupLng,
        'pickup_state':         _pickupState,
        'pickup_contact_name':  _pickupContactCtrl.text.trim().isEmpty
            ? null
            : _pickupContactCtrl.text.trim(),
        'pickup_contact_phone': _pickupPhoneCtrl.text.trim().isEmpty
            ? null
            : _pickupPhoneCtrl.text.trim(),
        'delivery_address':       _dropoffAddress,
        'delivery_lat':           _dropoffLat,
        'delivery_lng':           _dropoffLng,
        'delivery_contact_name':  _deliveryContactCtrl.text.trim().isEmpty
            ? null
            : _deliveryContactCtrl.text.trim(),
        'delivery_contact_phone': _deliveryPhoneCtrl.text.trim().isEmpty
            ? null
            : _deliveryPhoneCtrl.text.trim(),
        'package_description': desc,
        'package_value':       value,
        'status':              'open',
        'bid_closes_at':
            now.add(const Duration(hours: 24)).toIso8601String(),
      }).select().single();

      if (mounted) {
        Get.off(() => CustomerDeliveryDetailPage(
              deliveryId: result['id'] as String,
            ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack('Could not submit. Please try again.');
      }
    }
  }

  void _snack(String msg) => Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      backgroundColor: EzizaColors.kPurple,
      colorText: EzizaColors.kWhite,
      snackPosition: SnackPosition.BOTTOM);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Column(children: [
        _header(),
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // ── Pickup ───────────────────────────────────
                _sectionHeader('Pickup Details', Icons.radio_button_checked,
                    EzizaColors.kPurple),
                _card(children: [
                  _locationButton(
                    label: 'Pickup Location *',
                    address: _pickupAddress,
                    accentColor: EzizaColors.kPurple,
                    onTap: _pickPickup,
                  ),
                  const SizedBox(height: 14),
                  _field('Sender Name', _pickupContactCtrl,
                      hint: 'Name of person handing over package'),
                  const SizedBox(height: 14),
                  _field('Sender Phone', _pickupPhoneCtrl,
                      hint: '080xxxxxxxx',
                      type: TextInputType.phone),
                ]),
                const SizedBox(height: 8),

                // Connector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Container(
                        width: 2,
                        height: 24,
                        color: EzizaColors.kBorder),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_downward_rounded,
                        size: 16, color: EzizaColors.kMuted),
                  ]),
                ),
                const SizedBox(height: 8),

                // ── Delivery ─────────────────────────────────
                _sectionHeader(
                    'Delivery Details',
                    Icons.location_on_rounded,
                    EzizaColors.kGold),
                _card(children: [
                  _locationButton(
                    label: 'Dropoff Location *',
                    address: _dropoffAddress,
                    accentColor: EzizaColors.kGold,
                    onTap: _pickDropoff,
                  ),
                  const SizedBox(height: 14),
                  _field('Recipient Name', _deliveryContactCtrl,
                      hint: 'Name of person receiving package'),
                  const SizedBox(height: 14),
                  _field('Recipient Phone', _deliveryPhoneCtrl,
                      hint: '080xxxxxxxx',
                      type: TextInputType.phone),
                ]),
                const SizedBox(height: 16),

                // ── Package ──────────────────────────────────
                _sectionHeader('Package Info',
                    Icons.inventory_2_outlined, EzizaColors.kNavy),
                _card(children: [
                  _field('Package Description *', _descCtrl,
                      hint: 'e.g. Clothing items, 3 pieces',
                      maxLines: 2),
                  const SizedBox(height: 14),
                  _field('Estimated Value (₦, optional)', _valueCtrl,
                      hint: 'e.g. 15000',
                      type: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[\d.]'))
                      ]),
                ]),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: EzizaColors.kGold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              EzizaColors.kGold.withValues(alpha: 0.25))),
                  child: const Row(children: [
                    Icon(Icons.timer_outlined,
                        color: EzizaColors.kGold, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Riders and companies can bid on your request for 24 hours. '
                        "You'll review and accept the best offer.",
                        style: TextStyle(
                            fontSize: 12,
                            color: EzizaColors.kText,
                            height: 1.4),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),

                // ── Submit ────────────────────────────────────
                GestureDetector(
                  onTap: _submitting ? null : _submit,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: _submitting
                          ? null
                          : const LinearGradient(colors: [
                              EzizaColors.kPurple,
                              EzizaColors.kPurpleD
                            ]),
                      color:
                          _submitting ? EzizaColors.kBorder : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _submitting
                          ? null
                          : [
                              BoxShadow(
                                  color: EzizaColors.kPurple
                                      .withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5))
                            ],
                    ),
                    child: _submitting
                        ? const Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: EzizaColors.kWhite)))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_rounded,
                                  color: EzizaColors.kWhite, size: 18),
                              SizedBox(width: 8),
                              Text('Request Delivery',
                                  style: TextStyle(
                                      color: EzizaColors.kWhite,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            child: Row(children: [
              GestureDetector(
                onTap: Get.back,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1))),
                  child: const Icon(Icons.arrow_back_ios_new,
                      size: 16, color: EzizaColors.kWhite),
                ),
              ),
              const SizedBox(width: 14),
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Send a Package',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: EzizaColors.kWhite)),
                Text('Fill in the details below',
                    style: TextStyle(
                        fontSize: 12, color: Colors.white54)),
              ]),
            ]),
          ),
        ),
      );

  Widget _sectionHeader(String title, IconData icon, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: EzizaColors.kText)),
        ]),
      );

  Widget _card({required List<Widget> children}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: EzizaColors.kWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EzizaColors.kBorder),
            boxShadow: [
              BoxShadow(
                  color: EzizaColors.kPurple.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children),
      );

  Widget _locationButton({
    required String label,
    required String? address,
    required Color accentColor,
    required VoidCallback onTap,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: EzizaColors.kMuted)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: address != null
                  ? accentColor.withValues(alpha: 0.05)
                  : EzizaColors.kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: address != null
                    ? accentColor.withValues(alpha: 0.4)
                    : EzizaColors.kBorder,
              ),
            ),
            child: address != null
                ? Row(children: [
                    Icon(Icons.location_on_rounded,
                        size: 16, color: accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        address,
                        style: TextStyle(
                            fontSize: 13,
                            color: EzizaColors.kText,
                            height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.edit_location_alt_outlined,
                        size: 14, color: accentColor.withValues(alpha: 0.7)),
                  ])
                : Row(children: [
                    Icon(Icons.add_location_alt_outlined,
                        size: 16, color: accentColor),
                    const SizedBox(width: 10),
                    Text('Tap to pick location on map',
                        style: TextStyle(
                            fontSize: 13, color: EzizaColors.kMuted)),
                  ]),
          ),
        ),
      ]);

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    TextInputType? type,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: EzizaColors.kMuted)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: type,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          style: const TextStyle(
              fontSize: 14, color: EzizaColors.kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                color: EzizaColors.kMuted, fontSize: 13),
            filled: true,
            fillColor: EzizaColors.kSurface,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: EzizaColors.kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: EzizaColors.kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: EzizaColors.kPurple, width: 1.5)),
          ),
        ),
      ]);
}
