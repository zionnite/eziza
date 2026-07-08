import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';

class BunnyService {
  static String get _apiKey    => dotenv.env['BUNNY_STORAGE_API_KEY'] ?? '';
  static String get _zoneName  => dotenv.env['BUNNY_STORAGE_ZONE_NAME'] ?? '';
  // BUNNY_STORAGE_URL was never actually set in .env -- every upload() call
  // silently failed (relative-only URI, no scheme/host) until this was
  // switched to build the upload base from the zone name, which IS set.
  static String get _uploadBase => 'https://storage.bunnycdn.com/$_zoneName';
  static String get _pullZone  => dotenv.env['BUNNY_STORAGE_PULL_ZONE'] ?? ''; // eziza.b-cdn.net

  /// Uploads [file] to Bunny CDN at [storagePath] (no leading slash, no extension).
  /// Returns the public CDN URL on success, null on failure.
  static Future<String?> upload(XFile file, String storagePath) async {
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.path.split('.').last.toLowerCase();
      final path  = '$storagePath.$ext';

      final client  = HttpClient();
      final request = await client.putUrl(Uri.parse('$_uploadBase/$path'));
      request.headers.set('AccessKey',     _apiKey);
      request.headers.set('Content-Type',  'application/octet-stream');
      request.headers.set('Content-Length', bytes.length.toString());
      request.add(bytes);

      final response = await request.close();
      await response.drain<void>();
      client.close();

      if (response.statusCode == 201) {
        return 'https://$_pullZone/$path';
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
