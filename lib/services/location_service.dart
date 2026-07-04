import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  static Timer? _timer;
  static String? _activeRiderId;

  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // Start pushing GPS to Supabase every 10s (active delivery only)
  static void startTracking(String riderId) {
    _activeRiderId = riderId;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final pos = await getCurrentPosition();
      if (pos == null || _activeRiderId == null) return;
      await Supabase.instance.client.from('rider_locations').upsert({
        'rider_id':   _activeRiderId,
        'latitude':   pos.latitude,
        'longitude':  pos.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  static void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _activeRiderId = null;
  }
}
