import 'package:flutter_test/flutter_test.dart';

import 'package:architectula_education_app/services/report_repository.dart';

void main() {
  group('FlagReason', () {
    test('all reasons have non-empty labels', () {
      for (final reason in FlagReason.values) {
        expect(reason.label, isNotEmpty);
      }
    });

    test('all reasons have snake_case values', () {
      for (final reason in FlagReason.values) {
        expect(reason.value, matches(RegExp(r'^[a-z_]+$')));
      }
    });

    test('reason values are unique', () {
      final values = FlagReason.values.map((r) => r.value).toList();
      expect(values.toSet().length, equals(values.length));
    });

    test('incorrectAnswer maps to correct strings', () {
      expect(FlagReason.incorrectAnswer.value, 'incorrect_answer');
      expect(FlagReason.incorrectAnswer.label, 'Incorrect answer');
    });

    test('outdated maps to correct strings', () {
      expect(FlagReason.outdated.value, 'outdated');
      expect(FlagReason.outdated.label, 'Outdated');
    });

    test('unclearWording maps to correct strings', () {
      expect(FlagReason.unclearWording.value, 'unclear_wording');
      expect(FlagReason.unclearWording.label, 'Unclear wording');
    });

    test('other maps to correct strings', () {
      expect(FlagReason.other.value, 'other');
      expect(FlagReason.other.label, 'Other');
    });

    test('covers exactly 4 reasons', () {
      expect(FlagReason.values.length, 4);
    });
  });
}
