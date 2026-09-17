import 'dart:convert';

import 'package:are_coach/core/result.dart';
import 'package:are_coach/models/coach_answer.dart';
import 'package:are_coach/services/coach_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // CoachService reads FirebaseAuth.instance / FirebaseAppCheck.instance to
  // attach headers, both already wrapped in try/catch so a missing Firebase
  // app in the test VM (no plugins registered) degrades to "no header" the
  // same way a signed-out user or an AppCheck failure would in production.
  // No Firebase test setup is needed for that reason.

  const endpoint = 'https://example.test/askCoach';

  test('a 200 payload with sources produces a CoachAnswer carrying them, in order', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'answer': 'Required stair width is occupant load x 0.2 in/person.',
          'grounded': true,
          'sources': [
            {
              'source': 'nyc_bc_ch10_egress.pdf',
              'ref': '1005.3',
              'source_title': 'New York City Building Code',
              'source_page': 17,
            },
            {'source': 'ada_2010_standards.pdf', 'ref': '403.5.1'},
          ],
        }),
        200,
      );
    });
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('required egress width');

    expect(result, isA<Ok<CoachAnswer>>());
    final answer = (result as Ok<CoachAnswer>).value;
    expect(answer.answer, 'Required stair width is occupant load x 0.2 in/person.');
    expect(answer.grounded, isTrue);
    expect(answer.sources, hasLength(2));
    expect(answer.sources[0].source, 'nyc_bc_ch10_egress.pdf');
    expect(answer.sources[0].title, 'New York City Building Code');
    expect(answer.sources[1].source, 'ada_2010_standards.pdf');
    expect(answer.sources[1].title, isNull);
  });

  test('a 200 payload with no sources and grounded:false parses to an empty, ungrounded answer', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'answer': 'The ARE is scored pass/fail, one point per item.',
          'grounded': false,
          'sources': <dynamic>[],
        }),
        200,
      );
    });
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('how is the are scored');

    final answer = (result as Ok<CoachAnswer>).value;
    expect(answer.grounded, isFalse);
    expect(answer.sources, isEmpty);
  });

  test('a 200 payload missing sources/grounded still parses (older/partial payload shape)', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'answer': 'An answer.'}), 200);
    });
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('anything');

    final answer = (result as Ok<CoachAnswer>).value;
    expect(answer.answer, 'An answer.');
    expect(answer.grounded, isFalse);
    expect(answer.sources, isEmpty);
  });

  test('endpoint not configured at build time -- unchanged honest-failure message', () async {
    final client = MockClient((request) async => throw StateError('must not be called'));
    // No endpointOverride and no COACH_API_URL dart-define in this test run.
    final service = CoachService(client: client);

    final result = await service.askCoach('anything');

    expect(result, isA<Err<CoachAnswer>>());
    expect(
      (result as Err<CoachAnswer>).message,
      'Coach is unavailable in this build. Please update the app.',
    );
  });

  test('429 -- daily limit reached message is unchanged', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'limit': 10, 'used': 10}), 429);
    });
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('anything');

    expect(
      (result as Err<CoachAnswer>).message,
      'Daily AI limit reached (10/10). Upgrade to premium or try tomorrow.',
    );
  });

  test('401 -- authentication required message is unchanged', () async {
    final client = MockClient((request) async => http.Response('', 401));
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('anything');

    expect(
      (result as Err<CoachAnswer>).message,
      'Authentication required. Please re-open the app and try again.',
    );
  });

  test('503 -- coach-down message is unchanged', () async {
    final client = MockClient((request) async => http.Response('', 503));
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('anything');

    expect(
      (result as Err<CoachAnswer>).message,
      'Coach is temporarily unavailable. Please try again shortly.',
    );
  });

  test('a 200 payload with an empty answer is treated as a non-answer, not a crash', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'answer': '   '}), 200);
    });
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('anything');

    expect(
      (result as Err<CoachAnswer>).message,
      'Coach could not answer that. Please try rephrasing.',
    );
  });

  test('an unexpected status code falls through to the generic could-not-answer message', () async {
    final client = MockClient((request) async => http.Response('', 500));
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('anything');

    expect(
      (result as Err<CoachAnswer>).message,
      'Coach could not answer that. Please try rephrasing.',
    );
  });

  test('a network failure surfaces the unreachable-server message, never a canned answer', () async {
    final client = MockClient((request) async => throw Exception('socket closed'));
    final service = CoachService(client: client, endpointOverride: endpoint);

    final result = await service.askCoach('anything');

    expect(
      (result as Err<CoachAnswer>).message,
      'Could not reach the server. Check your connection and try again.',
    );
  });
}
