import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bunny_service.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;

  static User?    get currentUser    => _client.auth.currentUser;
  static Session? get currentSession => _client.auth.currentSession;
  static bool     get isLoggedIn     => currentSession != null;
  static SupabaseClient get client   => _client;

  // ── Auth ──────────────────────────────────────────────────────
  static Future<String> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) return 'Login failed, please try again';
      return 'true';
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> signOut() => _client.auth.signOut();

  // ── Simple registration (auth user only, no rider row) ─────────
  static Future<String> registerUser({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'register-user',
        body: {
          'email':    email,
          'password': password,
          'fullName': fullName,
          'phone':    phone,
        },
      );

      if (res.data?['error'] != null) return res.data['error'] as String;

      final signIn = await _client.auth.signInWithPassword(
        email: email, password: password,
      );
      if (signIn.user == null) return 'Account created — please log in';
      return 'true';
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return 'Registration failed';
    } catch (e) {
      return e.toString();
    }
  }

  // ── Rider application (user already logged in) ─────────────────
  static Future<String> applyAsRider({
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
    try {
      final uid = currentUser?.id;
      if (uid == null) return 'Not logged in';

      await _client.from('riders').insert({
        'auth_user_id':    uid,
        'full_name':       fullName,
        'phone':           phone,
        'email':           currentUser?.email,
        'vehicle_type':    vehicleType,
        'vehicle_plate':   vehiclePlate.isEmpty ? null : vehiclePlate,
        'coverage_states': coverageStates,
        'bank_name':       bankName.isEmpty ? null : bankName,
        'account_number':  accountNumber.isEmpty ? null : accountNumber,
        'account_name':    accountName.isEmpty ? null : accountName,
        'is_approved':     false,
        'status':          'pending',
      });

      // Upload docs to Bunny CDN (non-fatal)
      final govIdUrl  = govId  != null ? await BunnyService.upload(govId,  'rider-docs/$uid/gov_id')  : null;
      final selfieUrl = selfie != null ? await BunnyService.upload(selfie, 'rider-docs/$uid/selfie') : null;

      if (govIdUrl != null || selfieUrl != null) {
        await _client.from('riders').update({
          'gov_id_url': govIdUrl,
          'selfie_url': selfieUrl,
        }).eq('auth_user_id', uid);
      }

      return 'true';
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'You have already applied as a rider.';
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Legacy: combined register + rider row (kept for backward compat) ──
  static Future<String> signUpAndCreateRider({
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
    try {
      final res = await _client.functions.invoke(
        'register-rider',
        body: {
          'email':          email,
          'password':       password,
          'fullName':       fullName,
          'phone':          phone,
          'vehicleType':    vehicleType,
          'vehiclePlate':   vehiclePlate,
          'coverageStates': coverageStates,
          'bankName':       bankName,
          'accountNumber':  accountNumber,
          'accountName':    accountName,
        },
      );

      if (res.data?['error'] != null) return res.data['error'] as String;

      final signIn = await _client.auth.signInWithPassword(
        email: email, password: password,
      );
      if (signIn.user == null) {
        return 'Account created — please log in to continue';
      }

      final uid = signIn.user!.id;

      final govIdUrl  = govId  != null ? await BunnyService.upload(govId,  'rider-docs/$uid/gov_id')  : null;
      final selfieUrl = selfie != null ? await BunnyService.upload(selfie, 'rider-docs/$uid/selfie') : null;

      if (govIdUrl != null || selfieUrl != null) {
        await _client.from('riders').update({
          'gov_id_url': govIdUrl,
          'selfie_url': selfieUrl,
        }).eq('auth_user_id', uid);
      }

      return 'true';
    } on AuthException catch (e) {
      return e.message;
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return 'Registration failed';
    } catch (e) {
      return e.toString();
    }
  }

  // ── Earnings ──────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getCompletedDeliveries(
      String riderId) async {
    try {
      return List<Map<String, dynamic>>.from(await _client
          .from('deliveries')
          .select()
          .eq('rider_id', riderId)
          .eq('status', 'confirmed')
          .order('confirmed_at', ascending: false));
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getPayoutRequests(
      String riderId) async {
    try {
      return List<Map<String, dynamic>>.from(await _client
          .from('rider_payout_requests')
          .select()
          .eq('rider_id', riderId)
          .order('created_at', ascending: false));
    } catch (_) {
      return [];
    }
  }

  static Future<String> requestPayout({
    required String riderId,
    required double amount,
    required String bankName,
    required String accountNumber,
    required String accountName,
  }) async {
    try {
      await _client.from('rider_payout_requests').insert({
        'rider_id':       riderId,
        'amount':         amount,
        'bank_name':      bankName,
        'account_number': accountNumber,
        'account_name':   accountName,
      });
      return 'true';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Rider profile ─────────────────────────────────────────────
  static Future<String> updateRiderProfile({
    required String riderId,
    required String fullName,
    required String phone,
    required String vehicleType,
    required String vehiclePlate,
  }) async {
    try {
      await _client.from('riders').update({
        'full_name':       fullName,
        'phone':           phone,
        'vehicle_type':    vehicleType,
        'vehicle_plate':   vehiclePlate.isEmpty ? null : vehiclePlate,
      }).eq('id', riderId);
      return 'true';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> updateRiderBankDetails({
    required String riderId,
    required String bankName,
    required String accountNumber,
    required String accountName,
  }) async {
    try {
      await _client.from('riders').update({
        'bank_name':      bankName.isEmpty ? null : bankName,
        'account_number': accountNumber.isEmpty ? null : accountNumber,
        'account_name':   accountName.isEmpty ? null : accountName,
      }).eq('id', riderId);
      return 'true';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> updateAvailability(
      String riderId, bool isAvailable) async {
    try {
      await _client
          .from('riders')
          .update({'is_available': isAvailable})
          .eq('id', riderId);
    } catch (_) {}
  }

  static Future<void> updateFcmToken(String riderId, String token) async {
    try {
      await _client
          .from('riders')
          .update({'fcm_token': token})
          .eq('id', riderId);
    } catch (_) {}
  }

  static Future<void> saveDeviceToken(String token) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('device_tokens').upsert(
        {'auth_user_id': uid, 'token': token, 'updated_at': DateTime.now().toIso8601String()},
        onConflict: 'auth_user_id',
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getRiderProfile() async {
    try {
      final uid = currentUser?.id;
      if (uid == null) return null;
      return await _client
          .from('riders')
          .select()
          .eq('auth_user_id', uid)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setCustomerRole() async {
    try {
      await _client.auth.updateUser(
        UserAttributes(data: {'role': 'customer'}),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCompanyProfile() async {
    try {
      final uid = currentUser?.id;
      if (uid == null) return null;
      return await _client
          .from('companies')
          .select()
          .eq('auth_user_id', uid)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }
}
