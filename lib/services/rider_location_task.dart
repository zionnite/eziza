import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Called by the Android foreground service / iOS background task.
/// Runs in a separate Dart isolate — initialises its own Supabase instance.
@pragma('vm:entry-point')
void startRiderLocationCallback() {
  FlutterForegroundTask.setTaskHandler(RiderLocationTaskHandler());
}

class RiderLocationTaskHandler extends TaskHandler {
  SupabaseClient? _client;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final url  = await FlutterForegroundTask.getData<String>(key: 'sb_url') ?? '';
    final anon = await FlutterForegroundTask.getData<String>(key: 'sb_anon_key') ?? '';
    if (url.isEmpty) return;

    // Session is automatically restored from SharedPreferences
    // (same storage as the main isolate).
    await Supabase.initialize(url: url, publishableKey: anon);
    _client = Supabase.instance.client;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _pushLocation();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  Future<void> _pushLocation() async {
    final client = _client;
    final uid    = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 8));

      await client.from('rider_locations').upsert({
        'rider_id':   uid,
        'latitude':   pos.latitude,
        'longitude':  pos.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }
}
