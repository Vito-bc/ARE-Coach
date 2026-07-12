import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/result.dart';

class CoachService {
  CoachService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// True when the app was compiled with a real COACH_API_URL.
  static bool get isLive =>
      const String.fromEnvironment('COACH_API_URL').isNotEmpty;

  // There is deliberately no canned fallback answer.
  //
  // This class used to return a stock paragraph about egress width for EVERY
  // question whenever the endpoint was missing or the call failed — including
  // in production, where the release workflow never passed COACH_API_URL. A
  // wrong answer that looks authoritative is far worse than an honest outage:
  // the candidate studies a code section we invented. If the Coach cannot
  // answer, say so.

  Future<Result<String>> askCoach(String prompt) async {
    final endpoint = const String.fromEnvironment('COACH_API_URL');
    if (endpoint.isEmpty) {
      return const Err(
        'Coach is unavailable in this build. Please update the app.',
      );
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
        return Err('Daily AI limit reached ($used/$limit). Upgrade to premium or try tomorrow.');
      }

      if (response.statusCode == 401) {
        return const Err('Authentication required. Please re-open the app and try again.');
      }

      // The Coach itself is down (model unreachable, refused, misconfigured).
      // Surface it honestly — never paper over it with a stock answer.
      if (response.statusCode == 503) {
        return const Err('Coach is temporarily unavailable. Please try again shortly.');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = _asMap(response.body);
        final answer = payload['answer']?.toString();
        if (answer != null && answer.trim().isNotEmpty) {
          return Ok(answer);
        }
      }
      return const Err('Coach could not answer that. Please try rephrasing.');
    } catch (_) {
      return const Err('Could not reach the server. Check your connection and try again.');
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
