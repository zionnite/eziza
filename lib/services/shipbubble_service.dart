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

  /// Categories + box-size presets, fetched live from Shipbubble and cached
  /// server-side -- the customer picks from these before requesting rates.
  static Future<Map<String, dynamic>> getPackageOptions() async {
    final res = await _db.functions.invoke('shipbubble-package-options', body: {});
    final body = _body(res);
    if (res.status != 200) {
      throw Exception(body['error'] ?? 'Could not load package options (${res.status})');
    }
    return body;
  }

  static Future<List<Map<String, dynamic>>> fetchRates({
    required String deliveryId,
    required int categoryId,
    required Map<String, num> packageDimension, // {length, width, height} cm
    required double unitWeight, // kg
  }) async {
    final res = await _db.functions.invoke('shipbubble-fetch-rates', body: {
      'delivery_id':       deliveryId,
      'category_id':       categoryId,
      'package_dimension': packageDimension,
      'unit_weight':       unitWeight,
    });
    final body = _body(res);
    if (res.status != 200) {
      throw Exception(body['error'] ?? 'Could not get courier quotes (${res.status})');
    }
    return List<Map<String, dynamic>>.from(body['quotes'] as List? ?? []);
  }

  static Future<Map<String, dynamic>> bookShipment({required String quoteId}) async {
    final res = await _db.functions.invoke('shipbubble-book-shipment', body: {
      'quote_id': quoteId,
    });
    final body = _body(res);
    if (res.status != 200) {
      throw Exception(body['error'] ?? 'Could not book this courier (${res.status})');
    }
    return body;
  }

  static Future<void> cancelBooking({required String bookingId}) async {
    final res = await _db.functions.invoke('shipbubble-cancel', body: {
      'booking_id': bookingId,
    });
    final body = _body(res);
    if (res.status != 200) {
      throw Exception(body['error'] ?? 'Could not cancel this booking (${res.status})');
    }
  }
}
