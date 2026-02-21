import 'package:url_launcher/url_launcher.dart';
import 'location_service.dart';

class SosService {
  static String buildSosMessage({
    required bool isTest,
    required DateTime time,
    LocationSnapshot? location,
  }) {
    final t = time.toIso8601String();
    final locLine = (location == null)
        ? 'Location: unavailable'
        : 'Location: ${location.latitude}, ${location.longitude} (accuracy ±${location.accuracyMeters.toStringAsFixed(0)}m)\n'
          'Maps: https://maps.google.com/?q=${location.latitude},${location.longitude}';

    return [
      isTest ? '[TEST] Crash SOS' : 'Crash detected!',
      'Time: $t',
      locLine,
      'Please call me / send help.',
    ].join('\n');
  }

  // Opens the SMS composer (user presses Send)
  static Future<void> openSmsComposer({
    required String phoneNumber,
    required String body,
  }) async {
    final uri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: <String, String>{'body': body},
    );

    final ok = await canLaunchUrl(uri);
    if (!ok) {
      throw Exception('Cannot open SMS app on this device.');
    }
    await launchUrl(uri);
  }
}