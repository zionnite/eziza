import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../../models/rider.dart';

const _vehicleTypes = [
  ('bike',  'Bike',  Icons.two_wheeler_rounded),
  ('car',   'Car',   Icons.directions_car_rounded),
  ('van',   'Van',   Icons.airport_shuttle_rounded),
  ('truck', 'Truck', Icons.local_shipping_rounded),
];

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth    = Get.find<AuthController>();
  final _formKey = GlobalKey<FormState>();

  // Editable fields
  final _fullName      = TextEditingController();
  final _phone         = TextEditingController();
  final _plate         = TextEditingController();
  final _bankName      = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountName   = TextEditingController();
  String _vehicleType  = 'bike';

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefill(_auth.rider.value);
  }

  void _prefill(Rider? rider) {
    if (rider == null) return;
    _fullName.text      = rider.fullName;
    _phone.text         = rider.phone;
    _plate.text         = rider.vehiclePlate ?? '';
    _bankName.text      = rider.bankName ?? '';
    _accountNumber.text = rider.accountNumber ?? '';
    _accountName.text   = rider.accountName ?? '';
    _vehicleType        = rider.vehicleType;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _plate.dispose();
    _bankName.dispose();
    _accountNumber.dispose();
    _accountName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final result = await _auth.updateProfile(
        fullName:      _fullName.text.trim(),
        phone:         _phone.text.trim(),
        vehicleType:   _vehicleType,
        vehiclePlate:  _plate.text.trim(),
        bankName:      _bankName.text.trim(),
        accountNumber: _accountNumber.text.trim(),
        accountName:   _accountName.text.trim(),
      );
      if (!mounted) return;
      if (result == 'true') {
        Get.snackbar(
          'Saved', 'Your profile has been updated.',
          backgroundColor: EzizaColors.kSuccess,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kSurface,
      body: Obx(() {
        final rider = _auth.rider.value;
        if (rider == null) return const SizedBox.shrink();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroHeader(rider),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              _buildAvailabilityCard(rider),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Personal Info'),
                    const SizedBox(height: 12),
                    _field(
                      controller: _fullName,
                      label: 'Full Name',
                      icon: Icons.person_outline_rounded,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r"[a-zA-Z '-]")),
                      ],
                      validator: (v) =>
                          (v?.trim().isEmpty ?? true) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _phone,
                      label: 'Phone Number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Required';
                        if (val.length < 10) return 'Enter a valid phone number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    _sectionLabel('Vehicle'),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.4,
                      children: _vehicleTypes.map((t) {
                        final selected = _vehicleType == t.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _vehicleType = t.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: selected
                                  ? EzizaColors.kPurple
                                  : EzizaColors.kSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? EzizaColors.kPurple
                                    : EzizaColors.kBorder,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(t.$3,
                                    color: selected
                                        ? EzizaColors.kWhite
                                        : EzizaColors.kMuted,
                                    size: 20),
                                const SizedBox(width: 6),
                                Text(t.$2,
                                    style: TextStyle(
                                      color: selected
                                          ? EzizaColors.kWhite
                                          : EzizaColors.kText,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _plate,
                      label: 'Plate Number (optional)',
                      icon: Icons.credit_card_rounded,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9\-]')),
                        LengthLimitingTextInputFormatter(10),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _sectionLabel('Bank Details'),
                    const SizedBox(height: 12),
                    _field(
                      controller: _bankName,
                      label: 'Bank Name',
                      icon: Icons.account_balance_outlined,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _accountNumber,
                      label: 'Account Number',
                      icon: Icons.tag_rounded,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isNotEmpty && val.length != 10) {
                          return 'Must be exactly 10 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _accountName,
                      label: 'Account Name',
                      icon: Icons.person_outline_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
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
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: EzizaColors.kWhite, strokeWidth: 2))
                        : const Text('Save Changes',
                            style: TextStyle(
                                color: EzizaColors.kWhite,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── Hero header ────────────────────────────────────────────

  Widget _buildHeroHeader(Rider rider) {
    final initials = rider.fullName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    final (Color statusColor, String statusLabel) = switch (rider.status) {
      'approved'  => (const Color(0xFF4ADE80), 'Approved'),
      'rejected'  => (EzizaColors.kError, 'Rejected'),
      'suspended' => (Colors.orange, 'Suspended'),
      _           => (EzizaColors.kGold, 'Pending'),
    };

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A1A6E), EzizaColors.kNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x446C3483),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -22, top: 12,
              child: Container(
                width: 150, height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EzizaColors.kPurple.withValues(alpha: 0.13),
                ),
              ),
            ),
            Positioned(
              left: -16, bottom: 20,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EzizaColors.kGold.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top bar: title + sign out ─────────────
                  Row(
                    children: [
                      const Text(
                        'Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _auth.signOut(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.logout_rounded,
                                  size: 14, color: Colors.white70),
                              SizedBox(width: 6),
                              Text(
                                'Sign out',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  // ── Avatar + info ─────────────────────────
                  Row(
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: EzizaColors.kPurpleD.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rider.fullName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              rider.vehicleType[0].toUpperCase() +
                                  rider.vehicleType.substring(1),
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ── Stat pills ────────────────────────────
                  Wrap(
                    spacing: 8,
                    children: [
                      _heroPill(
                          '${rider.totalDeliveries}', 'Deliveries'),
                      if (rider.ratingAvg > 0)
                        _heroPill(
                            '${rider.ratingAvg.toStringAsFixed(1)} ⭐', 'Rating'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroPill(String value, String label) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$value ',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: label,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );

  // ── Availability toggle ────────────────────────────────────

  Widget _buildAvailabilityCard(Rider rider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: rider.isAvailable
            ? EzizaColors.kSuccess.withValues(alpha: 0.06)
            : EzizaColors.kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rider.isAvailable
              ? EzizaColors.kSuccess.withValues(alpha: 0.4)
              : EzizaColors.kBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: rider.isAvailable
                  ? EzizaColors.kSuccess.withValues(alpha: 0.12)
                  : EzizaColors.kBorder.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              rider.isAvailable
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: rider.isAvailable
                  ? EzizaColors.kSuccess
                  : EzizaColors.kMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rider.isAvailable ? 'Online' : 'Offline',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: rider.isAvailable
                          ? EzizaColors.kSuccess
                          : EzizaColors.kMuted),
                ),
                Text(
                  rider.isAvailable
                      ? 'You\'re visible to dispatchers'
                      : 'You won\'t receive new jobs',
                  style: const TextStyle(
                      color: EzizaColors.kMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Obx(() {
            final available = _auth.rider.value?.isAvailable ?? false;
            return Switch(
              value: available,
              activeThumbColor: EzizaColors.kSuccess,
              activeTrackColor: EzizaColors.kSuccess.withValues(alpha: 0.4),
              onChanged: (v) => _auth.setAvailability(v),
            );
          }),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: EzizaColors.kText),
      );

  TextFormField _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
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
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: EzizaColors.kPurple, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EzizaColors.kError),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
