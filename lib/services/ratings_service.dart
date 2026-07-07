import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared helpers for the 4 rating checkpoints (sender<->rider at handoff,
/// receiver<->rider at delivery). Kept here so each trigger site doesn't
/// duplicate the "already rated?" pre-check + insert shape.
class RatingsService {
  static final _db = Supabase.instance.client;

  /// True if this rater has already submitted a rating for this
  /// delivery/checkpoint/role — used to avoid re-showing the prompt on
  /// realtime re-triggers or repeated confirm taps.
  static Future<bool> hasRated({
    required String deliveryId,
    required String checkpoint,
    required String raterRole,
  }) async {
    try {
      final row = await _db
          .from('delivery_ratings')
          .select('id')
          .eq('delivery_id', deliveryId)
          .eq('checkpoint', checkpoint)
          .eq('rater_role', raterRole)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> submit({
    required String deliveryId,
    required String checkpoint,
    required String raterAuthId,
    required String raterRole,
    String? raterName,
    required String rateeRole,
    String? rateeId,
    required int rating,
    String? comment,
  }) async {
    await _db.from('delivery_ratings').insert({
      'delivery_id':   deliveryId,
      'checkpoint':    checkpoint,
      'rater_auth_id': raterAuthId,
      'rater_role':    raterRole,
      'rater_name':    raterName,
      'ratee_role':    rateeRole,
      'ratee_id':      rateeId,
      'rating':        rating,
      'comment':       comment,
    });
  }
}
