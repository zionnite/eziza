import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/delivery.dart';
import '../models/rider.dart';
import '../services/location_service.dart';

class DeliveryController extends GetxController {
  final _client = Supabase.instance.client;

  final openDeliveries   = <Delivery>[].obs;
  final activeDelivery   = Rxn<Delivery>();
  final loading          = false.obs;

  String? _riderId;
  RealtimeChannel? _channel;

  void init(Rider rider) {
    _riderId = rider.id;
    _loadOpen();
    _loadActive();
    _subscribeRealtime();
  }

  @override
  void onClose() {
    if (_channel != null) _client.removeChannel(_channel!);
    super.onClose();
  }

  // ── Open job board ────────────────────────────────────────
  Future<void> _loadOpen() async {
    loading.value = true;
    try {
      final rows = await _client
          .from('deliveries')
          .select()
          .eq('status', 'open')
          .order('created_at', ascending: false)
          .limit(50);
      openDeliveries.value = (rows as List).map((r) => Delivery.fromJson(r)).toList();
    } catch (_) {} finally {
      loading.value = false;
    }
  }

  // ── Active delivery (assigned to this rider) ──────────────
  Future<void> _loadActive() async {
    if (_riderId == null) return;
    try {
      final row = await _client
          .from('deliveries')
          .select()
          .eq('rider_id', _riderId!)
          .inFilter('status', ['assigned', 'awaiting_pickup_confirm', 'picked_up', 'delivered'])
          .maybeSingle();
      if (row != null) {
        activeDelivery.value = Delivery.fromJson(row);
        // Track continuously for the whole en-route window — merchants and
        // buyers need to see the rider heading to pickup too, not only
        // after they've picked up the package.
        const enRoute = ['assigned', 'awaiting_pickup_confirm', 'picked_up'];
        if (enRoute.contains(activeDelivery.value!.status)) {
          LocationService.startTracking(_riderId!);
        } else {
          LocationService.stopTracking();
        }
      } else {
        activeDelivery.value = null;
        LocationService.stopTracking();
      }
    } catch (_) {}
  }

  // ── Realtime: refresh on delivery table changes ───────────
  void _subscribeRealtime() {
    if (_channel != null) {
      _client.removeChannel(_channel!);
      _channel = null;
    }
    _channel = _client
        .channel('delivery_ctrl_${_riderId ?? 'anon'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          callback: (_) {
            _loadOpen();
            _loadActive();
          },
        )
        .subscribe();
  }

  // ── Place a bid ───────────────────────────────────────────
  Future<String> placeBid(String deliveryId, double amount, {String? note}) async {
    try {
      await _client.from('delivery_bids').insert({
        'delivery_id': deliveryId,
        'rider_id': _riderId,
        'amount': amount,
        'note': note,
      });
      return 'true';
    } catch (e) {
      return e.toString();
    }
  }

  // ── Status updates ────────────────────────────────────────
  Future<String> updateStatus(String deliveryId, String status) async {
    try {
      await _client
          .from('deliveries')
          .update({'status': status})
          .eq('id', deliveryId);

      // _loadActive() decides whether tracking should be running based on
      // the delivery's current status — no need to duplicate that logic here.
      await _loadActive();
      return 'true';
    } catch (e) {
      return e.toString();
    }
  }

  @override
  Future<void> refresh() async {
    await _loadOpen();
    await _loadActive();
  }
}
