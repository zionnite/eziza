import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rider.dart';
import '../services/fcm_service.dart';
import '../services/supabase_service.dart';

class AuthController extends GetxController {
  final rider          = Rxn<Rider>();
  final company        = Rxn<Map<String, dynamic>>();
  final isCustomer     = false.obs;
  final loggedIn       = false.obs;
  final profileLoading = true.obs;
  final loading        = false.obs;
  bool  _fcmReady = false;

  @override
  void onInit() {
    super.onInit();
    loggedIn.value = SupabaseService.isLoggedIn;
    _loadProfile();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        loggedIn.value = true;
        _loadProfile();
      }
      if (data.event == AuthChangeEvent.signedOut) {
        loggedIn.value       = false;
        rider.value          = null;
        company.value        = null;
        isCustomer.value     = false;
        _fcmReady            = false;
        profileLoading.value = false;
      }
    });
    // Initialize FCM for all logged-in users (riders, companies, customers).
    // Wait until profile loading finishes so the token save has auth context.
    ever(profileLoading, (bool loading) {
      if (!loading && loggedIn.value && !_fcmReady) {
        _fcmReady = true;
        FcmService.initialize();
      }
    });
  }

  Future<void> _loadProfile() async {
    profileLoading.value = true;
    final riderJson = await SupabaseService.getRiderProfile();
    rider.value = riderJson != null ? Rider.fromJson(riderJson) : null;

    if (rider.value == null) {
      company.value = await SupabaseService.getCompanyProfile();
      // Check if this user previously identified as a customer
      final role = SupabaseService.currentUser?.userMetadata?['role'] as String?;
      isCustomer.value = company.value == null && role == 'customer';
    } else {
      company.value    = null;
      isCustomer.value = false;
    }

    profileLoading.value = false;
  }

  // ── Auth ───────────────────────────────────────────────────────
  Future<String> signIn(String email, String password) async {
    loading.value = true;
    try {
      return await SupabaseService.signIn(email: email, password: password);
    } finally {
      loading.value = false;
    }
  }

  Future<void> signOut() async {
    await SupabaseService.signOut();
  }

  // ── Simple registration (creates auth user only) ───────────────
  Future<String> registerUser({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    loading.value = true;
    try {
      return await SupabaseService.registerUser(
        email:    email,
        password: password,
        fullName: fullName,
        phone:    phone,
      );
    } finally {
      loading.value = false;
    }
  }

  // ── Apply as rider (user already logged in) ────────────────────
  Future<String> applyAsRider({
    required String fullName,
    required String phone,
    required String vehicleType,
    required String vehiclePlate,
    required List<String> coverageStates,
    required String bankName,
    required String accountNumber,
    required String accountName,
    XFile? govId,
    XFile? selfie,
  }) async {
    loading.value = true;
    try {
      final result = await SupabaseService.applyAsRider(
        fullName:       fullName,
        phone:          phone,
        vehicleType:    vehicleType,
        vehiclePlate:   vehiclePlate,
        coverageStates: coverageStates,
        bankName:       bankName,
        accountNumber:  accountNumber,
        accountName:    accountName,
        govId:          govId,
        selfie:         selfie,
      );
      if (result == 'true') await _loadProfile();
      return result;
    } finally {
      loading.value = false;
    }
  }

  // ── Legacy: combined register + rider application ──────────────
  Future<String> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String vehicleType,
    required String vehiclePlate,
    required List<String> coverageStates,
    required String bankName,
    required String accountNumber,
    required String accountName,
    XFile? govId,
    XFile? selfie,
  }) async {
    loading.value = true;
    try {
      return await SupabaseService.signUpAndCreateRider(
        email:          email,
        password:       password,
        fullName:       fullName,
        phone:          phone,
        vehicleType:    vehicleType,
        vehiclePlate:   vehiclePlate,
        coverageStates: coverageStates,
        bankName:       bankName,
        accountNumber:  accountNumber,
        accountName:    accountName,
        govId:          govId,
        selfie:         selfie,
      );
    } finally {
      loading.value = false;
    }
  }

  // ── Profile ────────────────────────────────────────────────────
  Future<String> updateProfile({
    required String fullName,
    required String phone,
    required String vehicleType,
    required String vehiclePlate,
    required String bankName,
    required String accountNumber,
    required String accountName,
  }) async {
    final id = rider.value?.id;
    if (id == null) return 'Not logged in';
    loading.value = true;
    try {
      final result = await SupabaseService.updateRiderProfile(
        riderId:       id,
        fullName:      fullName,
        phone:         phone,
        vehicleType:   vehicleType,
        vehiclePlate:  vehiclePlate,
        bankName:      bankName,
        accountNumber: accountNumber,
        accountName:   accountName,
      );
      if (result == 'true') await _loadProfile();
      return result;
    } finally {
      loading.value = false;
    }
  }

  Future<void> setAvailability(bool isAvailable) async {
    final id = rider.value?.id;
    if (id == null) return;
    await SupabaseService.updateAvailability(id, isAvailable);
    await _loadProfile();
  }

  Future<void> refreshProfile() => _loadProfile();

  bool get isApproved => rider.value?.isApproved ?? false;
}
