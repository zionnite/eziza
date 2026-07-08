import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../services/bank_service.dart';

const _vehicleTypes = [
  ('bike',    'Bike',    Icons.two_wheeler_rounded),
  ('bicycle', 'Bicycle', Icons.directions_bike_rounded),
  ('car',     'Car',     Icons.directions_car_rounded),
  ('van',     'Van',     Icons.airport_shuttle_rounded),
  ('foot',    'On Foot', Icons.directions_walk_rounded),
];

const _nigerianStates = [
  'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa',
  'Benue', 'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo',
  'Ekiti', 'Enugu', 'FCT', 'Gombe', 'Imo', 'Jigawa', 'Kaduna',
  'Kano', 'Katsina', 'Kebbi', 'Kogi', 'Kwara', 'Lagos', 'Nasarawa',
  'Niger', 'Ogun', 'Ondo', 'Osun', 'Oyo', 'Plateau', 'Rivers',
  'Sokoto', 'Taraba', 'Yobe', 'Zamfara',
];

const _steps = [
  ('Vehicle', 'How do you deliver?'),
  ('Coverage', 'Where do you operate?'),
  ('Documents', 'Verify your identity'),
  ('Bank', 'How should we pay you?'),
];

class RiderApplicationPage extends StatefulWidget {
  const RiderApplicationPage({super.key});

  @override
  State<RiderApplicationPage> createState() => _RiderApplicationPageState();
}

class _RiderApplicationPageState extends State<RiderApplicationPage>
    with SingleTickerProviderStateMixin {
  final _auth   = Get.find<AuthController>();
  final _db     = Supabase.instance.client;
  final _picker = ImagePicker();

  // Existing application state
  String? _existingStatus; // null = no application yet
  bool _checking = true;

  // Step controller
  int _step = 0;
  bool _loading = false;
  final _formKeys = List.generate(4, (_) => GlobalKey<FormState>());

  // Step 0 – Vehicle
  String _vehicleType = 'bike';
  final _plate = TextEditingController();

  // Step 1 – Coverage
  final _selectedStates = <String>{};
  final _stateSearch    = TextEditingController();

  // Step 2 – Documents
  XFile? _govId;
  XFile? _selfie;

  // Step 3 – Bank
  List<Bank> _banks        = [];
  bool       _banksLoading = true;
  Bank?      _selectedBank;
  final _accountNumber = TextEditingController();
  final _accountName   = TextEditingController();

  // Rider name/phone from auth metadata (pre-filled)
  String _fullName = '';
  String _phone    = '';

  @override
  void initState() {
    super.initState();
    _prefillFromAuth();
    _checkExisting();
    _loadBanks();
  }

  void _prefillFromAuth() {
    final meta = _db.auth.currentUser?.userMetadata;
    _fullName = (meta?['full_name'] as String?) ?? '';
    _phone    = (meta?['phone']     as String?) ?? '';
  }

  Future<void> _checkExisting() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;
      final row = await _db
          .from('riders')
          .select('status, is_approved')
          .eq('auth_user_id', uid)
          .maybeSingle();
      if (row != null) {
        final approved = row['is_approved'] as bool? ?? false;
        _existingStatus = row['status'] as String?
            ?? (approved ? 'approved' : 'pending');
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _loadBanks() async {
    final banks = await BankService.fetchBanks();
    if (mounted) setState(() { _banks = banks; _banksLoading = false; });
  }

  @override
  void dispose() {
    _plate.dispose();
    _stateSearch.dispose();
    _accountNumber.dispose();
    _accountName.dispose();
    super.dispose();
  }

  bool _validateCurrent() {
    if (_step == 2) return true; // docs optional
    return _formKeys[_step].currentState?.validate() ?? false;
  }

  void _next() {
    if (!_validateCurrent()) return;
    if (_step < 3) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _submit() async {
    if (!(_formKeys[3].currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      final result = await _auth.applyAsRider(
        fullName:       _fullName,
        phone:          _phone,
        vehicleType:    _vehicleType,
        vehiclePlate:   _plate.text.trim(),
        coverageStates: _selectedStates.toList(),
        bankName:       _selectedBank?.name ?? '',
        bankCode:       _selectedBank?.code ?? '',
        accountNumber:  _accountNumber.text.trim(),
        accountName:    _accountName.text.trim(),
        govId:          _govId,
        selfie:         _selfie,
      );
      if (!mounted) return;
      if (result == 'true') {
        Get.until((route) => route.isFirst);
        Get.snackbar(
          'Application Submitted',
          'Your rider application is under review. We\'ll notify you once approved.',
          backgroundColor: EzizaColors.kPurple,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 5),
        );
      } else {
        Get.snackbar(
          'Error', result,
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<XFile?> _pickImage(ImageSource source) async {
    try {
      return await _picker.pickImage(
          source: source, imageQuality: 80, maxWidth: 1200);
    } catch (_) {
      return null;
    }
  }

  void _showImageSourceSheet(ValueSetter<XFile?> onPicked) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: EzizaColors.kBorder,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded,
                color: EzizaColors.kPurple),
            title: const Text('Choose from Gallery'),
            onTap: () async {
              Navigator.pop(context);
              onPicked(await _pickImage(ImageSource.gallery));
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded,
                color: EzizaColors.kPurple),
            title: const Text('Take a Photo'),
            onTap: () async {
              Navigator.pop(context);
              onPicked(await _pickImage(ImageSource.camera));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kWhite,
      body: SafeArea(
        child: _checking
            ? const Center(
                child: CircularProgressIndicator(color: EzizaColors.kPurple))
            : _existingStatus != null
                ? _buildStatusView()
                : _buildApplicationForm(),
      ),
    );
  }

  // ── Already applied — show status ─────────────────────────────

  Widget _buildStatusView() {
    final status = _existingStatus ?? 'pending';
    late Color color;
    late IconData icon;
    late String title;
    late String body;

    switch (status) {
      case 'approved':
        color = EzizaColors.kSuccess;
        icon  = Icons.check_circle_rounded;
        title = 'Application Approved!';
        body  = 'Your rider account is active. You can start accepting deliveries.';
        break;
      case 'rejected':
        color = EzizaColors.kError;
        icon  = Icons.cancel_rounded;
        title = 'Application Rejected';
        body  = 'Unfortunately your application was not approved. Contact support for more info.';
        break;
      case 'suspended':
        color = Colors.orange;
        icon  = Icons.block_rounded;
        title = 'Account Suspended';
        body  = 'Your rider account has been suspended. Please contact support.';
        break;
      default:
        color = EzizaColors.kGold;
        icon  = Icons.hourglass_top_rounded;
        title = 'Application Under Review';
        body  = 'We are reviewing your application. You\'ll be notified once approved.';
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: color),
          const SizedBox(height: 24),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: EzizaColors.kText)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: EzizaColors.kMuted, fontSize: 14, height: 1.5)),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back_rounded,
                color: EzizaColors.kPurple),
            label: const Text('Go Back',
                style: TextStyle(color: EzizaColors.kPurple)),
          ),
        ],
      ),
    );
  }

  // ── Application form ─────────────────────────────────────────

  Widget _buildApplicationForm() {
    final progress = (_step + 1) / 4;

    return Column(children: [
      // Header
      Container(
        color: EzizaColors.kWhite,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                color: EzizaColors.kText,
                onPressed: _step == 0 ? () => Get.back() : _back,
              ),
              const Spacer(),
              Text('Step ${_step + 1} of 4',
                  style: const TextStyle(
                      color: EzizaColors.kMuted, fontSize: 13)),
            ]),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Padding(
              key: ValueKey(_step),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_steps[_step].$1,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: EzizaColors.kText)),
                const SizedBox(height: 4),
                Text(_steps[_step].$2,
                    style: const TextStyle(
                        color: EzizaColors.kMuted, fontSize: 14)),
              ]),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: progress, end: progress),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            builder: (_, value, _) => LinearProgressIndicator(
              value: value,
              backgroundColor: EzizaColors.kBorder,
              valueColor:
                  const AlwaysStoppedAnimation(EzizaColors.kPurple),
              minHeight: 3,
            ),
          ),
        ]),
      ),

      // Step content
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: switch (_step) {
                0 => _buildStepVehicle(),
                1 => _buildStepCoverage(),
                2 => _buildStepDocs(),
                3 => _buildStepBank(),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ),
      ),

      // Footer
      Container(
        decoration: const BoxDecoration(
          color: EzizaColors.kWhite,
          border: Border(top: BorderSide(color: EzizaColors.kBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Row(children: [
          if (_step > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _back,
                style: OutlinedButton.styleFrom(
                  foregroundColor: EzizaColors.kText,
                  side: const BorderSide(color: EzizaColors.kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: _primaryBtn(
              label: _step == 3 ? 'Submit Application' : 'Continue',
              onPressed: _loading ? null : (_step == 3 ? _submit : _next),
              isLoading: _loading,
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Step 0: Vehicle ───────────────────────────────────────────

  Widget _buildStepVehicle() {
    return Form(
      key: _formKeys[0],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Vehicle Type',
            style: TextStyle(
                color: EzizaColors.kMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: _vehicleTypes.map((t) {
            final sel = _vehicleType == t.$1;
            return GestureDetector(
              onTap: () => setState(() => _vehicleType = t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: sel ? EzizaColors.kPurple : EzizaColors.kSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: sel ? EzizaColors.kPurple : EzizaColors.kBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(t.$3,
                      color: sel ? EzizaColors.kWhite : EzizaColors.kMuted,
                      size: 22),
                  const SizedBox(width: 8),
                  Text(t.$2,
                      style: TextStyle(
                          color: sel ? EzizaColors.kWhite : EzizaColors.kText,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        _field(
          controller: _plate,
          label: 'Plate Number (optional)',
          hint: 'e.g. LND-123AB',
          icon: Icons.credit_card_rounded,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
            LengthLimitingTextInputFormatter(10),
          ],
        ),
      ]),
    );
  }

  // ── Step 1: Coverage ─────────────────────────────────────────

  Widget _buildStepCoverage() {
    return Form(
      key: _formKeys[1],
      child: FormField<Set<String>>(
        initialValue: _selectedStates,
        validator: (_) =>
            _selectedStates.isEmpty ? 'Select at least one state' : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _stateSearch,
              onChanged: (_) => setState(() {}),
              decoration: _inputDec('Search states',
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: EzizaColors.kMuted)),
            ),
            const SizedBox(height: 16),
            if (_selectedStates.isNotEmpty) ...[
              Row(children: [
                Text(
                  '${_selectedStates.length} state${_selectedStates.length == 1 ? '' : 's'} selected',
                  style: const TextStyle(
                      color: EzizaColors.kPurple,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selectedStates.clear()),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: const Size(40, 28)),
                  child: const Text('Clear all',
                      style: TextStyle(color: EzizaColors.kError, fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _nigerianStates
                  .where((s) => s
                      .toLowerCase()
                      .contains(_stateSearch.text.toLowerCase()))
                  .map((state) {
                final selected = _selectedStates.contains(state);
                return FilterChip(
                  label: Text(state,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected
                              ? EzizaColors.kPurple
                              : EzizaColors.kText)),
                  selected: selected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedStates.add(state);
                      } else {
                        _selectedStates.remove(state);
                      }
                      field.didChange(_selectedStates);
                    });
                  },
                  selectedColor:
                      EzizaColors.kPurple.withValues(alpha: 0.12),
                  checkmarkColor: EzizaColors.kPurple,
                  backgroundColor: EzizaColors.kSurface,
                  side: BorderSide(
                    color: selected ? EzizaColors.kPurple : EzizaColors.kBorder,
                  ),
                  showCheckmark: true,
                );
              }).toList(),
            ),
            if (field.hasError) ...[
              const SizedBox(height: 8),
              Text(field.errorText!,
                  style: const TextStyle(
                      color: EzizaColors.kError, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  // ── Step 2: Documents ─────────────────────────────────────────

  Widget _buildStepDocs() {
    return Form(
      key: _formKeys[2],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EzizaColors.kGold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EzizaColors.kGold.withValues(alpha: 0.4)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: EzizaColors.kGold, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Documents are optional — you can upload them later from your profile.',
                  style: TextStyle(
                      color: EzizaColors.kText, fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _docCard(
          label: 'Government-Issued ID',
          subtitle: 'NIN slip, driver\'s licence, voter card, or passport',
          icon: Icons.badge_outlined,
          file: _govId,
          onTap: () => _showImageSourceSheet(
              (f) => setState(() => _govId = f ?? _govId)),
        ),
        const SizedBox(height: 16),
        _docCard(
          label: 'Selfie Holding ID',
          subtitle: 'Take a clear photo of yourself holding your ID',
          icon: Icons.face_retouching_natural_rounded,
          file: _selfie,
          onTap: () => _showImageSourceSheet(
              (f) => setState(() => _selfie = f ?? _selfie)),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _step < 3 ? _next : null,
          icon: const Icon(Icons.skip_next_rounded,
              color: EzizaColors.kMuted, size: 18),
          label: const Text('Skip for now',
              style: TextStyle(color: EzizaColors.kMuted)),
        ),
      ]),
    );
  }

  Widget _docCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required XFile? file,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: file != null
                ? EzizaColors.kPurple.withValues(alpha: 0.05)
                : EzizaColors.kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: file != null ? EzizaColors.kPurple : EzizaColors.kBorder,
              width: file != null ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            if (file != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(file.path),
                    width: 64, height: 64, fit: BoxFit.cover),
              )
            else
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                    color: EzizaColors.kBorder,
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: EzizaColors.kMuted, size: 28),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: EzizaColors.kText,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  file != null
                      ? '✓ Photo selected — tap to change'
                      : subtitle,
                  style: TextStyle(
                      color:
                          file != null ? EzizaColors.kSuccess : EzizaColors.kMuted,
                      fontSize: 12,
                      height: 1.4),
                ),
              ]),
            ),
            Icon(
              file != null
                  ? Icons.check_circle_rounded
                  : Icons.camera_alt_outlined,
              color:
                  file != null ? EzizaColors.kSuccess : EzizaColors.kMuted,
            ),
          ]),
        ),
      );

  // ── Step 3: Bank ─────────────────────────────────────────────

  Widget _buildStepBank() {
    return Form(
      key: _formKeys[3],
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_banksLoading)
          InputDecorator(
            decoration: _inputDec('Bank Name',
                prefixIcon: const Icon(Icons.account_balance_outlined,
                    color: EzizaColors.kMuted)),
            child: const Row(children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: EzizaColors.kPurple)),
              SizedBox(width: 12),
              Text('Loading banks…',
                  style: TextStyle(color: EzizaColors.kMuted)),
            ]),
          )
        else
          DropdownButtonFormField<Bank>(
            initialValue: _selectedBank,
            decoration: _inputDec('Bank Name',
                prefixIcon: const Icon(Icons.account_balance_outlined,
                    color: EzizaColors.kMuted)),
            hint: const Text('Select your bank',
                style: TextStyle(color: EzizaColors.kMuted)),
            items: _banks
                .map((b) =>
                    DropdownMenuItem(value: b, child: Text(b.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedBank = v),
            validator: (v) => v == null ? 'Required' : null,
            icon: const Icon(Icons.expand_more_rounded,
                color: EzizaColors.kMuted),
            borderRadius: BorderRadius.circular(12),
          ),
        const SizedBox(height: 16),
        _field(
          controller: _accountNumber,
          label: 'Account Number',
          hint: '10-digit NUBAN',
          icon: Icons.tag_rounded,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          validator: (v) {
            final val = v?.trim() ?? '';
            if (val.isEmpty) return 'Required';
            if (val.length != 10) return 'Must be exactly 10 digits';
            return null;
          },
        ),
        const SizedBox(height: 16),
        _field(
          controller: _accountName,
          label: 'Account Name',
          hint: 'Name on your bank account',
          icon: Icons.person_outline_rounded,
          validator: (v) =>
              (v?.trim().isEmpty ?? true) ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: EzizaColors.kSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EzizaColors.kBorder)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.security_rounded, color: EzizaColors.kPurple, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your bank details are encrypted and used only for processing payout.',
                style: TextStyle(
                    color: EzizaColors.kMuted, fontSize: 12, height: 1.5),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  Widget _primaryBtn({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) =>
      SizedBox(
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [EzizaColors.kPurpleD, EzizaColors.kPurple]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: EzizaColors.kPurple.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: EzizaColors.kWhite, strokeWidth: 2))
                : Text(label,
                    style: const TextStyle(
                        color: EzizaColors.kWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
          ),
        ),
      );

  TextFormField _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: const TextStyle(color: EzizaColors.kText),
        decoration: _inputDec(label, hint: hint,
            prefixIcon: Icon(icon, color: EzizaColors.kMuted, size: 20)),
      );

  InputDecoration _inputDec(
    String label, {
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: EzizaColors.kMuted),
        hintStyle: const TextStyle(color: EzizaColors.kMuted),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: EzizaColors.kSurface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: EzizaColors.kPurple, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kError)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: EzizaColors.kError, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
}
