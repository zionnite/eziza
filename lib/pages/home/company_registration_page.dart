import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/colors.dart';
import '../../models/location.dart';
import '../../services/bank_service.dart';
import '../../services/coverage_location_service.dart';

class CompanyRegistrationPage extends StatefulWidget {
  const CompanyRegistrationPage({super.key});

  @override
  State<CompanyRegistrationPage> createState() =>
      _CompanyRegistrationPageState();
}

class _CompanyRegistrationPageState extends State<CompanyRegistrationPage>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;

  final _companyNameCtrl = TextEditingController();
  final _cacCtrl         = TextEditingController();
  final _contactCtrl     = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _acctNumberCtrl  = TextEditingController();
  final _acctNameCtrl    = TextEditingController();

  // Coverage — list of selected Location objects (deduped by id)
  final _selectedAreas = <Location>[];

  // Bank
  List<Bank> _banks        = [];
  bool       _banksLoading = true;
  String?    _bankCode;
  String?    _bankName;

  bool _submitting    = false;
  bool _submitted     = false;
  bool _alreadyApplied = false;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _init();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _companyNameCtrl.dispose();
    _cacCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _acctNumberCtrl.dispose();
    _acctNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    // Pre-fill from auth metadata
    _contactCtrl.text = user.userMetadata?['full_name'] as String? ?? '';
    _phoneCtrl.text   = user.userMetadata?['phone']     as String? ?? '';

    // Check if already applied
    final existing = await _db
        .from('companies')
        .select('id')
        .eq('auth_user_id', user.id)
        .maybeSingle();
    if (existing != null && mounted) {
      setState(() => _alreadyApplied = true);
      return;
    }

    // Load banks
    final banks = await BankService.fetchBanks();
    if (mounted) setState(() { _banks = banks; _banksLoading = false; });
  }

  // ── Location picker ──────────────────────────────────────────

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationPickerSheet(
        onAreasAdded: (areas) {
          setState(() {
            for (final a in areas) {
              if (!_selectedAreas.any((s) => s.id == a.id)) {
                _selectedAreas.add(a);
              }
            }
          });
        },
      ),
    );
  }

  // ── Bank picker ──────────────────────────────────────────────

  void _showBankPicker() {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = _banks
              .where((b) =>
                  b.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: const BoxDecoration(
                color: EzizaColors.kWhite,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _sheetHandle(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  _sheetIcon(Icons.account_balance_outlined),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Select Bank',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: EzizaColors.kText)),
                      Text("Company's settlement bank",
                          style: TextStyle(
                              fontSize: 12, color: EzizaColors.kMuted)),
                    ]),
                  ),
                  if (_bankCode != null)
                    _clearBtn(() {
                      Navigator.pop(ctx);
                      setState(() { _bankCode = null; _bankName = null; });
                    }),
                ]),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _searchField('Search bank…',
                    onChanged: (v) => setSheet(() => query = v)),
              ),
              const SizedBox(height: 8),
              const Divider(color: EzizaColors.kBorder, height: 1),
              Expanded(
                child: _banksLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: EzizaColors.kPurple))
                    : ListView.separated(
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, i) => const Divider(
                            height: 1,
                            color: EzizaColors.kBorder,
                            indent: 20,
                            endIndent: 20),
                        itemBuilder: (_, i) {
                          final b   = filtered[i];
                          final sel = _bankCode == b.code;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 4),
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: sel
                                      ? EzizaColors.kPurple
                                          .withValues(alpha: 0.1)
                                      : EzizaColors.kSurface,
                                  borderRadius:
                                      BorderRadius.circular(8)),
                              child: Icon(
                                  Icons.account_balance_rounded,
                                  size: 18,
                                  color: sel
                                      ? EzizaColors.kPurple
                                      : EzizaColors.kMuted)),
                            title: Text(b.name,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: sel
                                        ? EzizaColors.kPurple
                                        : EzizaColors.kText)),
                            trailing: sel
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: EzizaColors.kPurple,
                                    size: 20)
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              setState(
                                  () { _bankName = b.name; _bankCode = b.code; });
                            },
                          );
                        },
                      ),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ── Submit ───────────────────────────────────────────────────

  Future<void> _submit() async {
    final company  = _companyNameCtrl.text.trim();
    final contact  = _contactCtrl.text.trim();
    final phone    = _phoneCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final acctNum  = _acctNumberCtrl.text.trim();
    final acctName = _acctNameCtrl.text.trim();

    if (company.isEmpty) { _snack('Enter your company name.'); return; }
    if (contact.isEmpty) { _snack('Enter the contact person name.'); return; }
    if (phone.isEmpty)   { _snack('Enter a contact phone number.'); return; }
    if (_selectedAreas.isEmpty) {
      _snack('Select at least one coverage area.');
      return;
    }
    if (_bankCode == null || acctNum.isEmpty || acctName.isEmpty) {
      _snack('Complete your bank details.');
      return;
    }

    final user = _db.auth.currentUser;
    if (user == null) { _snack('Not logged in.'); return; }

    setState(() => _submitting = true);
    try {
      await _db.from('companies').insert({
        'auth_user_id':      user.id,
        'name':              company,
        'cac_number':        _cacCtrl.text.trim().isEmpty
            ? null
            : _cacCtrl.text.trim(),
        'contact_person':    contact,
        'phone':             phone,
        'email':             email.isEmpty ? null : email,
        'state':             _selectedAreas.first.state,
        'coverage_area_ids': _selectedAreas.map((a) => a.id).toList(),
        'bank_name':         _bankName,
        'account_number':    acctNum,
        'account_name':      acctName,
        'bank_code':         _bankCode,
        'status':            'pending',
      });
      if (mounted) setState(() { _submitted = true; _submitting = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        _snack('Submission failed: ${e.toString()}');
      }
    }
  }

  void _snack(String msg) => Get.snackbar('', msg,
      titleText: const SizedBox.shrink(),
      backgroundColor: EzizaColors.kPurple,
      colorText: EzizaColors.kWhite,
      snackPosition: SnackPosition.BOTTOM);

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: _alreadyApplied
                ? _buildAlreadyApplied()
                : _submitted
                    ? _buildSuccess()
                    : _buildForm(),
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader() => Container(
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
                onTap: () => Get.back(),
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
                Text('Register a Company',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: EzizaColors.kWhite)),
                Text('Partner with Eziza as a logistics company',
                    style: TextStyle(
                        fontSize: 12, color: Colors.white54)),
              ]),
            ]),
          ),
        ),
      );

  Widget _buildAlreadyApplied() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _statusIcon(Icons.business_center_outlined),
            const SizedBox(height: 20),
            const Text('Application on File',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: EzizaColors.kText)),
            const SizedBox(height: 10),
            const Text(
              'You already have a company application submitted. '
              'Contact support if you need to make changes.',
              style: TextStyle(
                  fontSize: 14, color: EzizaColors.kMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _gradientButton('Back to Home', Get.back),
          ]),
        ),
      );

  Widget _buildSuccess() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _statusIcon(Icons.check_circle_outline_rounded),
            const SizedBox(height: 20),
            const Text('Application Submitted!',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: EzizaColors.kText)),
            const SizedBox(height: 10),
            const Text(
              "Your company application is under review. We'll get back "
              'to you within 2–5 business days.',
              style: TextStyle(
                  fontSize: 14, color: EzizaColors.kMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            _gradientButton('Back to Home', Get.back),
          ]),
        ),
      );

  Widget _buildForm() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Company info ─────────────────────────────────────
          _sectionHeader('Company Info', Icons.business_outlined),
          _card(children: [
            _field('Company Name', _companyNameCtrl,
                hint: 'Registered business name'),
            const SizedBox(height: 14),
            _field('CAC Number (optional)', _cacCtrl,
                hint: 'e.g. RC-1234567',
                inputFormatters: [_UpperCaseFormatter()]),
          ]),
          const SizedBox(height: 16),

          // ── Contact ──────────────────────────────────────────
          _sectionHeader('Contact Details', Icons.person_outline),
          _card(children: [
            _field('Contact Person', _contactCtrl,
                hint: 'Manager or director name'),
            const SizedBox(height: 14),
            _field('Phone', _phoneCtrl,
                hint: '080xxxxxxxx',
                type: TextInputType.phone),
            const SizedBox(height: 14),
            _field('Email (optional)', _emailCtrl,
                hint: 'company@example.com',
                type: TextInputType.emailAddress),
          ]),
          const SizedBox(height: 16),

          // ── Coverage areas ───────────────────────────────────
          _sectionHeader('Coverage Areas', Icons.map_outlined),
          _card(children: [
            const Text(
              'Add all areas your company can deliver to.',
              style: TextStyle(
                  fontSize: 12, color: EzizaColors.kMuted, height: 1.4)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _showLocationPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: EzizaColors.kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: EzizaColors.kPurple)),
                child: const Row(children: [
                  Icon(Icons.add_location_alt_outlined,
                      size: 18, color: EzizaColors.kPurple),
                  SizedBox(width: 8),
                  Text('Add coverage area',
                      style: TextStyle(
                          fontSize: 13,
                          color: EzizaColors.kPurple,
                          fontWeight: FontWeight.w600)),
                  Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: EzizaColors.kPurple),
                ]),
              ),
            ),
            if (_selectedAreas.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedAreas.map((loc) => Container(
                  padding: const EdgeInsets.only(
                      left: 10, top: 5, bottom: 5, right: 6),
                  decoration: BoxDecoration(
                      color: EzizaColors.kPurple.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: EzizaColors.kPurple
                              .withValues(alpha: 0.25))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(
                        loc.shortDisplay,
                        style: const TextStyle(
                            fontSize: 11,
                            color: EzizaColors.kPurple,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(
                          () => _selectedAreas.remove(loc)),
                      child: const Icon(Icons.close_rounded,
                          size: 13, color: EzizaColors.kPurple),
                    ),
                  ]),
                )).toList(),
              ),
            ],
          ]),
          const SizedBox(height: 16),

          // ── Bank details ─────────────────────────────────────
          _sectionHeader('Bank Details', Icons.account_balance_outlined),
          _card(children: [
            GestureDetector(
              onTap: _banksLoading ? null : _showBankPicker,
              child: Row(children: [
                Icon(
                  _bankCode != null
                      ? Icons.account_balance_rounded
                      : Icons.account_balance_outlined,
                  size: 17,
                  color: _bankCode != null
                      ? EzizaColors.kPurple
                      : EzizaColors.kMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _banksLoading
                        ? 'Loading banks…'
                        : _bankName ?? 'Select your bank',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: _bankCode != null
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: _bankCode != null
                            ? EzizaColors.kText
                            : EzizaColors.kMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_banksLoading)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: EzizaColors.kMuted))
                else
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: _bankCode != null
                          ? EzizaColors.kPurple
                          : EzizaColors.kMuted),
              ]),
            ),
            const SizedBox(height: 14),
            _field('Account Number', _acctNumberCtrl,
                hint: '0000000000',
                type: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ]),
            const SizedBox(height: 14),
            _field('Account Name', _acctNameCtrl,
                hint: 'As on your bank account'),
          ]),
          const SizedBox(height: 28),

          // ── Submit ────────────────────────────────────────────
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
                color: _submitting ? EzizaColors.kBorder : null,
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
                  : const Text('Submit Application',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: EzizaColors.kWhite,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'By submitting, you confirm the information is accurate '
            'and authorised on behalf of the company.',
            style: TextStyle(
                fontSize: 11, color: EzizaColors.kMuted, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ]),
      );

  // ── Shared small widgets ─────────────────────────────────────

  Widget _statusIcon(IconData icon) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: EzizaColors.kPurple.withValues(alpha: 0.1),
            shape: BoxShape.circle),
        child:
            Icon(icon, size: 56, color: EzizaColors.kPurple));

  Widget _gradientButton(String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: EzizaColors.kPurple.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ]),
          child: Text(label,
              style: const TextStyle(
                  color: EzizaColors.kWhite,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
      );

  Widget _sectionHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: EzizaColors.kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: EzizaColors.kPurple, size: 16),
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

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    TextInputType? type,
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
          inputFormatters: inputFormatters,
          style:
              const TextStyle(fontSize: 14, color: EzizaColors.kText),
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

// ── 3-step location picker bottom sheet ───────────────────────

class _LocationPickerSheet extends StatefulWidget {
  final void Function(List<Location>) onAreasAdded;

  const _LocationPickerSheet({required this.onAreasAdded});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  // Steps: 1 = state list, 2 = city list, 3 = area multi-select
  int    _step        = 1;
  String _query       = '';
  String _state       = '';
  String _city        = '';

  List<String>   _states = [];
  List<String>   _cities = [];
  List<Location> _areas  = [];

  final _searchCtrl = TextEditingController();

  bool _loading = false;

  final _selectedAreas = <Location>{};

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStates() async {
    setState(() => _loading = true);
    CoverageLocationService.clearCache();
    final states = await CoverageLocationService.fetchStates();
    if (mounted) setState(() { _states = states; _loading = false; });
  }

  Future<void> _selectState(String state) async {
    setState(() { _state = state; _step = 2; _loading = true; _query = ''; _searchCtrl.clear(); });
    final cities = await CoverageLocationService.fetchCities(state);
    if (mounted) setState(() { _cities = cities; _loading = false; });
  }

  Future<void> _selectCity(String city) async {
    setState(() { _city = city; _step = 3; _loading = true; _query = ''; _searchCtrl.clear(); _selectedAreas.clear(); });
    final areas = await CoverageLocationService.fetchAreas(_state, city);
    if (mounted) setState(() { _areas = areas; _loading = false; });
  }

  void _goBack() {
    setState(() {
      _query = '';
      _searchCtrl.clear();
      if (_step == 3) { _step = 2; _selectedAreas.clear(); }
      else if (_step == 2) { _step = 1; }
    });
  }

  void _confirmAreas() {
    widget.onAreasAdded(_selectedAreas.toList());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
          color: EzizaColors.kWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetHandle(),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(children: [
            if (_step > 1)
              GestureDetector(
                onTap: _goBack,
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: EzizaColors.kSurface,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: EzizaColors.kBorder)),
                  child: const Icon(Icons.arrow_back_ios_new,
                      size: 14, color: EzizaColors.kText),
                ),
              ),
            _sheetIcon(Icons.add_location_alt_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  _step == 1
                      ? 'Select State'
                      : _step == 2
                          ? 'Select City — $_state'
                          : 'Select Areas — $_city',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: EzizaColors.kText),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _step == 1
                      ? 'Step 1 of 3'
                      : _step == 2
                          ? 'Step 2 of 3'
                          : 'Step 3 of 3 — tap to select',
                  style: const TextStyle(
                      fontSize: 11, color: EzizaColors.kMuted),
                ),
              ]),
            ),
            // Step indicators
            Row(children: List.generate(3, (i) => Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                  color: (i + 1) <= _step
                      ? EzizaColors.kPurple
                      : EzizaColors.kBorder,
                  shape: BoxShape.circle),
            ))),
          ]),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: _searchField(
            _step == 1
                ? 'Search state…'
                : _step == 2
                    ? 'Search city…'
                    : 'Search area…',
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const Divider(color: EzizaColors.kBorder, height: 1),
        // List
        Expanded(child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    color: EzizaColors.kPurple))
            : _buildList()),
        // Confirm button (step 3 only)
        if (_step == 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: GestureDetector(
              onTap:
                  _selectedAreas.isEmpty ? null : _confirmAreas,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  gradient: _selectedAreas.isNotEmpty
                      ? const LinearGradient(colors: [
                          EzizaColors.kPurple,
                          EzizaColors.kPurpleD
                        ])
                      : null,
                  color: _selectedAreas.isEmpty
                      ? EzizaColors.kBorder
                      : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _selectedAreas.isEmpty
                      ? 'Select at least one area'
                      : 'Add ${_selectedAreas.length} area${_selectedAreas.length != 1 ? 's' : ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _selectedAreas.isEmpty
                          ? EzizaColors.kMuted
                          : EzizaColors.kWhite,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildList() {
    if (_step == 1) {
      final list = _states
          .where((s) =>
              s.toLowerCase().contains(_query.toLowerCase()))
          .toList();
      if (list.isEmpty) return _emptyState('No states found');
      return ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) => ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          title: Text(list[i],
              style: const TextStyle(
                  fontSize: 14, color: EzizaColors.kText)),
          trailing: const Icon(Icons.chevron_right_rounded,
              size: 18, color: EzizaColors.kMuted),
          onTap: () => _selectState(list[i]),
        ),
      );
    }

    if (_step == 2) {
      final list = _cities
          .where((c) =>
              c.toLowerCase().contains(_query.toLowerCase()))
          .toList();
      if (list.isEmpty) return _emptyState('No cities found');
      return ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) => ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          title: Text(list[i],
              style: const TextStyle(
                  fontSize: 14, color: EzizaColors.kText)),
          trailing: const Icon(Icons.chevron_right_rounded,
              size: 18, color: EzizaColors.kMuted),
          onTap: () => _selectCity(list[i]),
        ),
      );
    }

    // Step 3: multi-select areas
    final list = _areas
        .where((a) =>
            a.area.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    if (list.isEmpty) return _emptyState('No areas found');
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final area = list[i];
        final sel  = _selectedAreas.contains(area);
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: sel ? EzizaColors.kPurple : Colors.transparent,
                border: Border.all(
                    color: sel
                        ? EzizaColors.kPurple
                        : EzizaColors.kBorder,
                    width: 1.5),
                borderRadius: BorderRadius.circular(5)),
            child: sel
                ? const Icon(Icons.check_rounded,
                    size: 14, color: EzizaColors.kWhite)
                : null,
          ),
          title: Text(area.area,
              style: TextStyle(
                  fontSize: 14,
                  color: EzizaColors.kText,
                  fontWeight:
                      sel ? FontWeight.w700 : FontWeight.w400)),
          onTap: () => setState(() {
            if (sel) {
              _selectedAreas.remove(area);
            } else {
              _selectedAreas.add(area);
            }
          }),
        );
      },
    );
  }

  Widget _emptyState(String msg) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off_rounded,
              size: 40, color: EzizaColors.kBorder),
          const SizedBox(height: 8),
          Text(msg,
              style: const TextStyle(
                  color: EzizaColors.kMuted, fontSize: 13)),
        ]),
      );
}

// ── Shared helpers ────────────────────────────────────────────

Widget _sheetHandle() => Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      decoration: BoxDecoration(
          color: EzizaColors.kBorder,
          borderRadius: BorderRadius.circular(2)));

Widget _sheetIcon(IconData icon) => Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: EzizaColors.kPurple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 18, color: EzizaColors.kPurple));

Widget _clearBtn(VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.red.shade200)),
        child: Text('Clear',
            style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade600,
                fontWeight: FontWeight.w700)),
      ),
    );

Widget _searchField(
  String hint, {
  TextEditingController? controller,
  void Function(String)? onChanged,
}) =>
    TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: EzizaColors.kText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: EzizaColors.kMuted, fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded,
            color: EzizaColors.kMuted, size: 20),
        filled: true,
        fillColor: EzizaColors.kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: EzizaColors.kPurple, width: 1.5)),
      ),
    );

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue old, TextEditingValue n) =>
      n.copyWith(
          text: n.text.toUpperCase(), selection: n.selection);
}
