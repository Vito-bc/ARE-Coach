import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class CoachService {
  CoachService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// True when the app was compiled with a real COACH_API_URL.
  static bool get isLive =>
      const String.fromEnvironment('COACH_API_URL').isNotEmpty;

  static const _fallback = '''
Formula:
Required width = Occupant load x egress factor.
For stairs in many exam problems: 300 x 0.2 = 60 in.

Code:
Check IBC Section 1005.3.1 and local NYC amendments.

Exam note:
This is often a 10-15 point competency question. Typical mistakes: using 0.15 for stairs or forgetting minimum clear widths.
''';

  Future<String> askCoach(String prompt) async {
    final endpoint = const String.fromEnvironment('COACH_API_URL');
    if (endpoint.isEmpty) {
      return _fallback;
    }

    try {
      String? token;
      String? appCheckToken;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {
        token = null;
      }
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken();
      } catch (_) {
        appCheckToken = null;
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      if (appCheckToken != null && appCheckToken.isNotEmpty) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }

      final response = await _client.post(
        Uri.parse(endpoint),
        headers: headers,
        body: jsonEncode({'prompt': prompt}),
      );

      if (response.statusCode == 429) {
        final payload = _asMap(response.body);
        final limit = payload['limit'];
        final used = payload['used'];
        return 'Daily AI limit reached ($used/$limit). Upgrade to premium or try tomorrow.';
      }

      if (response.statusCode == 401) {
        return 'Authentication required. Please re-open the app and try again.';
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = _asMap(response.body);
        final answer = payload['answer']?.toString();
        if (answer != null && answer.trim().isNotEmpty) {
          return answer;
        }
      }
      return _fallback;
    } catch (_) {
      return _fallback;
    }
  }

  Map<String, dynamic> _asMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }

  void dispose() => _client.close();
}
