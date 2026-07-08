import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/colors.dart';
import 'controllers/auth_controller.dart';
import 'controllers/delivery_controller.dart';
import 'pages/auth/reset_password_page.dart';
import 'pages/auth/splash_page.dart';
import 'pages/auth/welcome_page.dart';
import 'pages/customer/customer_dashboard_page.dart';
import 'pages/home/company_dashboard_page.dart';
import 'pages/home/home_page.dart';
import 'pages/home/rider_dashboard_page.dart';
import 'services/fcm_service.dart';

// Required top-level handler for background FCM messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) =>
    firebaseMessagingBackgroundHandler(message);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  Get.put(AuthController());
  Get.put(DeliveryController());

  runApp(const EzizaRiderApp());
}

class EzizaRiderApp extends StatefulWidget {
  const EzizaRiderApp({super.key});

  @override
  State<EzizaRiderApp> createState() => _EzizaRiderAppState();
}

class _EzizaRiderAppState extends State<EzizaRiderApp> {
  @override
  void initState() {
    super.initState();
    // Supabase's own deep-link handling catches the eziza://reset link
    // (registered natively alongside eziza://wallet-topup-complete) and
    // emits this event once the recovery session is ready -- no need to
    // manually intercept the URI ourselves. Mirrors ZeeFashion's main.dart.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        Get.to(() => const ResetPasswordPage());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Eziza',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: EzizaColors.kPurple),
        useMaterial3: true,
        scaffoldBackgroundColor: EzizaColors.kWhite,
        appBarTheme: const AppBarTheme(
          backgroundColor: EzizaColors.kWhite,
          surfaceTintColor: EzizaColors.kWhite,
          elevation: 0,
          iconTheme: IconThemeData(color: EzizaColors.kText),
          titleTextStyle: TextStyle(
            color: EzizaColors.kText,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      home: const SplashPage(),
    );
  }
}

class AuthRouter extends StatelessWidget {
  const AuthRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(() {
      // Show loading while checking session / fetching profile
      if (auth.profileLoading.value) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: EzizaColors.kPurple),
          ),
        );
      }

      if (!auth.loggedIn.value) return const WelcomePage();

      final rider = auth.rider.value;

      if (rider != null) {
        // Hard blocks only for explicitly rejected/suspended accounts
        if (rider.status == 'rejected')  return const _RejectedPage();
        if (rider.status == 'suspended') return const _SuspendedPage();
        // Pending OR approved → dashboard (status banner shown inside)
        return const RiderDashboardPage();
      }

      // No rider row — check for company
      if (auth.company.value != null) return const CompanyDashboardPage();

      // Returning customer (previously chose "send a package")
      if (auth.isCustomer.value) return const CustomerDashboardPage();

      // Brand new user — show role selection
      return const UserHomePage();
    });
  }
}

class _RejectedPage extends StatelessWidget {
  const _RejectedPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel_outlined, size: 72, color: EzizaColors.kError),
              const SizedBox(height: 24),
              const Text('Application Not Approved',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: EzizaColors.kText)),
              const SizedBox(height: 12),
              const Text(
                'Your rider application was not successful at this time. '
                'Please contact support for more information.',
                textAlign: TextAlign.center,
                style: TextStyle(color: EzizaColors.kMuted, height: 1.5),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => Get.find<AuthController>().signOut(),
                child: const Text('Sign out',
                    style: TextStyle(color: EzizaColors.kPurple)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuspendedPage extends StatelessWidget {
  const _SuspendedPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block_rounded, size: 72, color: Colors.orange),
              const SizedBox(height: 24),
              const Text('Account Suspended',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: EzizaColors.kText)),
              const SizedBox(height: 12),
              const Text(
                'Your account has been suspended. Please contact Eziza support '
                'to resolve this.',
                textAlign: TextAlign.center,
                style: TextStyle(color: EzizaColors.kMuted, height: 1.5),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => Get.find<AuthController>().signOut(),
                child: const Text('Sign out',
                    style: TextStyle(color: EzizaColors.kPurple)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
