import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../constants/colors.dart';
import '../../controllers/auth_controller.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _obscure   = true;

  final _auth = Get.find<AuthController>();

  Future<void> _submit() async {
    final email    = _email.text.trim();
    final password = _password.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    final result = await _auth.signIn(email, password);
    if (result != 'true' && mounted) {
      Get.snackbar('Error', result,
          backgroundColor: EzizaColors.kError,
          colorText: EzizaColors.kWhite,
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EzizaColors.kWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              // Logo / Brand
              Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: const BoxDecoration(
                    color: EzizaColors.kPurple,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delivery_dining,
                      color: EzizaColors.kWhite, size: 28),
                ),
                const SizedBox(width: 12),
                const Text('Eziza',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: EzizaColors.kText)),
              ]),
              const SizedBox(height: 12),
              const Text('Rider Portal',
                  style: TextStyle(color: EzizaColors.kMuted, fontSize: 15)),
              const SizedBox(height: 48),
              const Text('Sign In',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: EzizaColors.kText)),
              const SizedBox(height: 24),

              // Email
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('Email address'),
              ),
              const SizedBox(height: 16),

              // Password
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: _inputDecoration('Password').copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: EzizaColors.kMuted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Forgot / register links
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 32),
                  ),
                  child: const Text('Forgot password?',
                      style: TextStyle(
                          color: EzizaColors.kPurple, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 16),

              // Submit
              Obx(() => SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      EzizaColors.kPurpleD,
                      EzizaColors.kPurple,
                    ]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: EzizaColors.kPurple.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _auth.loading.value ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _auth.loading.value
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: EzizaColors.kWhite, strokeWidth: 2))
                        : const Text('Sign In',
                            style: TextStyle(
                                color: EzizaColors.kWhite,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
              )),
              const SizedBox(height: 32),

              // Register link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?",
                      style: TextStyle(
                          color: EzizaColors.kMuted, fontSize: 14)),
                  TextButton(
                    onPressed: () =>
                        Get.to(() => const RegisterPage(),
                            transition: Transition.rightToLeft),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    child: const Text('Register',
                        style: TextStyle(
                            color: EzizaColors.kPurple,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: EzizaColors.kMuted),
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
          borderSide: const BorderSide(color: EzizaColors.kPurple, width: 1.5),
        ),
      );
}
