import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import '../shared/eula_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _auth    = Get.find<AuthController>();
  final _formKey = GlobalKey<FormState>();

  final _fullName = TextEditingController();
  final _phone    = TextEditingController();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _confirm  = TextEditingController();

  bool _obscurePwd = true;
  bool _obscureCfm = true;
  bool _loading    = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      final result = await _auth.registerUser(
        email:    _email.text.trim(),
        password: _password.text.trim(),
        fullName: _fullName.text.trim(),
        phone:    _phone.text.trim(),
      );
      if (!mounted) return;
      if (result == 'true') {
        // Auth state change will update AuthRouter to show UserHomePage
        Get.until((route) => route.isFirst);
      } else {
        Get.snackbar(
          'Registration Failed', result,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kWhite,
      body: Stack(children: [
        Positioned(
          top: -100, right: -80,
          child: Container(
            width: 280, height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [EzizaColors.kPurple.withValues(alpha: 0.08), Colors.transparent]),
            ),
          ),
        ),
        Positioned(
          bottom: 120, left: -40,
          child: Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [EzizaColors.kGold.withValues(alpha: 0.07), Colors.transparent]),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: EzizaColors.kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EzizaColors.kBorder),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, size: 15, color: EzizaColors.kText),
                  ),
                ),
                const SizedBox(height: 28),
                Row(children: [
                  Container(
                    width: 14, height: 2,
                    decoration: BoxDecoration(color: EzizaColors.kPurple, borderRadius: BorderRadius.circular(1)),
                    margin: const EdgeInsets.only(right: 8),
                  ),
                  Text('GET STARTED', style: TextStyle(color: EzizaColors.kPurple.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                ]),
                const SizedBox(height: 10),
                const Text(
                  'Create\nAccount',
                  style: TextStyle(
                      color: EzizaColors.kText,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Join Eziza to send, track, and deliver',
                  style: TextStyle(color: EzizaColors.kMuted, fontSize: 14),
                ),
                const SizedBox(height: 32),
                _field(
                  controller: _fullName,
                  label: 'Full Name',
                  hint: 'e.g. Chukwuemeka Obi',
                  icon: Icons.person_outline_rounded,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z '\-]")),
                  ],
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _phone,
                  label: 'Phone Number',
                  hint: '08012345678',
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
                const SizedBox(height: 16),
                _field(
                  controller: _email,
                  label: 'Email Address',
                  hint: 'you@example.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final val = v?.trim() ?? '';
                    if (val.isEmpty) return 'Required';
                    if (!val.contains('@') || !val.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _password,
                  label: 'Password',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePwd,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePwd ? Icons.visibility_off : Icons.visibility,
                      color: EzizaColors.kMuted,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePwd = !_obscurePwd),
                  ),
                  validator: (v) =>
                      (v?.length ?? 0) < 8 ? 'Minimum 8 characters' : null,
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _confirm,
                  label: 'Confirm Password',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscureCfm,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCfm ? Icons.visibility_off : Icons.visibility,
                      color: EzizaColors.kMuted,
                    ),
                    onPressed: () =>
                        setState(() => _obscureCfm = !_obscureCfm),
                  ),
                  validator: (v) =>
                      v != _password.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Get.to(() => const EulaPage()),
                  child: RichText(
                    text: TextSpan(children: [
                      const TextSpan(
                        text: 'By creating an account you agree to our ',
                        style: TextStyle(color: EzizaColors.kMuted, fontSize: 12, height: 1.5),
                      ),
                      TextSpan(
                        text: 'End-User License Agreement',
                        style: TextStyle(
                          color: EzizaColors.kPurple,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: EzizaColors.kPurple.withValues(alpha: 0.4),
                        ),
                      ),
                      const TextSpan(
                        text: '.',
                        style: TextStyle(color: EzizaColors.kMuted, fontSize: 12, height: 1.5),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
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
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: EzizaColors.kWhite, strokeWidth: 2))
                          : const Text('Create Account',
                              style: TextStyle(
                                  color: EzizaColors.kWhite,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          ),
        ),
      ]),
    );
  }

  TextFormField _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) =>
      TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: const TextStyle(color: EzizaColors.kText),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: EzizaColors.kMuted),
          hintStyle: const TextStyle(color: EzizaColors.kMuted),
          prefixIcon: Icon(icon, color: EzizaColors.kMuted, size: 20),
          suffixIcon: suffixIcon,
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
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: EzizaColors.kError, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );
}
