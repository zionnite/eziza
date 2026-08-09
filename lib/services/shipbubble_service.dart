import 'package:supabase_flutter/supabase_flutter.dart';

/// Client wrapper for the 5 shipbubble-* edge functions. The Shipbubble
/// secret key never touches this app -- every call goes server-side, same
/// reasoning as WalletService/paystack-initialize. All 4 customer-facing
/// calls forward the caller's own session automatically via
/// `_db.functions.invoke` (Supabase Flutter includes the current JWT).
class ShipbubbleService {
  static final _db = Supabase.instance.client;

  static Map<String, dynamic> _body(FunctionResponse res) =>
      (res.data as Map?)?.cast<String, dynamic>() ?? {};

  // supabase_flutter's functions.invoke() throws FunctionException itself
  // for any non-2xx response -- it never returns a FunctionResponse with
  // .status set to the error code for a caller to check afterward. Every
  // `if (res.status != 200) throw Exception(...)` below this used to be
  // dead code for real errors: the raw FunctionException(status:.., details:
  // {...}, reasonPhrase:..) propagated straight past it to whatever UI
  // caught it (confirmed live 2026-08-10 -- a friendly address-validation
  // message from shipbubble-fetch-rates was showing as that raw dump).
  // Centralized here instead of patching every UI catch site individually.
  static Future<T> _invoke<T>(
    String function,
    Map<String, dynamic> body,
    String fallbackError,
    T Function(Map<String, dynamic> body) onSuccess,
  ) async {
    try {
      final res = await _db.functions.invoke(function, body: body);
      return onSuccess(_body(res));
    } on FunctionException catch (e) {
      final details = e.details;
      final message = (details is Map ? details['error']?.toString() : null) ?? e.reasonPhrase ?? fallbackError;
      throw Exception(message);
    }
  }

  /// Categories + box-size presets, fetched live from Shipbubble and cached
  /// server-side -- the customer picks from these before requesting rates.
  static Future<Map<String, dynamic>> getPackageOptions() =>
      _invoke('shipbubble-package-options', {}, 'Could not load package options', (b) => b);

  static Future<List<Map<String, dynamic>>> fetchRates({
    required String deliveryId,
    required int categoryId,
    required Map<String, num> packageDimension, // {length, width, height} cm
    required double unitWeight, // kg
  }) =>
      _invoke(
        'shipbubble-fetch-rates',
        {
          'delivery_id':       deliveryId,
          'category_id':       categoryId,
          'package_dimension': packageDimension,
          'unit_weight':       unitWeight,
        },
        'Could not get courier quotes',
        (b) => List<Map<String, dynamic>>.from(b['quotes'] as List? ?? []),
      );

  static Future<Map<String, dynamic>> bookShipment({required String quoteId}) =>
      _invoke('shipbubble-book-shipment', {'quote_id': quoteId}, 'Could not book this courier', (b) => b);

  static Future<void> cancelBooking({required String bookingId}) =>
      _invoke('shipbubble-cancel', {'booking_id': bookingId}, 'Could not cancel this booking', (_) {});
}
