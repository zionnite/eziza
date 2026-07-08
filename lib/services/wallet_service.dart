import 'package:supabase_flutter/supabase_flutter.dart';

/// Customer wallet: balance/history reads, Paystack top-up initialization,
/// and the two payment-bearing RPCs (accept-bid-with-payment, cancel-with-
/// refund). The Paystack secret key never touches this app — top-up goes
/// through paystack-initialize (server-side), and the actual credit lands
/// via paystack-webhook once Paystack confirms charge.success. This
/// deliberately does not use the pay_with_paystack package, which requires
/// shipping the real secret key client-side (verified against its source —
/// it calls api.paystack.co directly with `Authorization: Bearer <secretKey>`).
class WalletService {
  static final _db = Supabase.instance.client;

  static Future<double> getBalance(String customerId) async {
    final row = await _db
        .from('customers')
        .select('wallet_balance')
        .eq('id', customerId)
        .maybeSingle();
    return (row?['wallet_balance'] as num?)?.toDouble() ?? 0.0;
  }

  static Future<List<Map<String, dynamic>>> getTransactions(String customerId) async {
    final rows = await _db
        .from('wallet_transactions')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Returns the Paystack checkout URL to open (in an in-app browser view).
  /// The actual credit is applied asynchronously by paystack-webhook once
  /// Paystack confirms the charge — this call does not itself move money.
  static Future<String> initializeTopUp({
    required String customerId,
    required String email,
    required double amount,
  }) async {
    final session = _db.auth.currentSession;
    if (session == null) throw Exception('Not logged in');

    final reference = 'topup_${customerId.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}';

    final res = await _db.functions.invoke(
      'paystack-initialize',
      body: {
        'email':       email,
        'amount':      amount,
        'customer_id': customerId,
        'reference':   reference,
      },
    );

    final body = (res.data as Map?)?.cast<String, dynamic>() ?? {};
    if (res.status != 200 || body['authorization_url'] == null) {
      throw Exception(body['error'] ?? 'Could not start payment (${res.status})');
    }
    return body['authorization_url'] as String;
  }

  /// Atomic: checks wallet balance, debits it, accepts the bid, rejects the
  /// others. Throws with a clear message on insufficient balance.
  static Future<void> acceptBidWithPayment({
    required String bidId,
    required String customerId,
  }) async {
    await _db.rpc('pay_and_accept_delivery_bid', params: {
      'p_bid_id':      bidId,
      'p_customer_id': customerId,
    });
  }

  /// Cancels an open/assigned delivery, refunding the wallet if it was paid.
  static Future<void> cancelDelivery({
    required String deliveryId,
    required String customerId,
    String? reason,
  }) async {
    await _db.rpc('cancel_delivery_with_refund', params: {
      'p_delivery_id': deliveryId,
      'p_customer_id': customerId,
      'p_reason':      reason,
    });
  }
}
