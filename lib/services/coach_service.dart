import 'dart:convert';

import 'package:http/http.dart' as http;

class CoachService {
  CoachService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

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
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
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

  void dispose() => _client.close();
}
