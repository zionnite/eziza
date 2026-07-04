import 'dart:convert';
import 'dart:io';
import 'package:latlong2/latlong.dart';

class NominatimService {
  static Future<LatLng?> geocode(String address) async {
    try {
      final client = HttpClient();
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$address, Nigeria',
        'format': 'json',
        'limit': '1',
      });
      final req = await client.getUrl(uri);
      req.headers.set(
          'User-Agent', 'EzizaRiderApp/1.0 (contact@eziza.com)');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as List;
      if (data.isEmpty) return null;
      return LatLng(
        double.parse(data[0]['lat'] as String),
        double.parse(data[0]['lon'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
