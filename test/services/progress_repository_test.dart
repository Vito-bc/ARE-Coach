import 'package:architectula_education_app/services/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Builds a session map with questionResults for the given section → correctness list.
Map<String, dynamic> _session(Map<String, List<bool>> sectionResults) {
  final results = <Map<String, dynamic>>[];
  for (final entry in sectionResults.entries) {
    for (final isCorrect in entry.value) {
      results.add({'section': entry.key, 'isCorrect': isCorrect});
    }
  }
  return {'questionResults': results};
}

void main() {
  // ── computeReadiness ────────────────────────────────────────────────────────

  group('computeReadiness', () {
    test('returns 42 placeholder when no scores', () {
      expect(ProgressRepository.computeReadiness([]), 42);
    });

    test('returns exact score for single session', () {
      expect(ProgressRepository.computeReadiness([80]), 80);
    });

    test('returns rounded average across sessions', () {
      expect(ProgressRepository.computeReadiness([70, 80]), 75);
    });

    test('rounds 0.5 up', () {
      // 70 + 71 = 141 / 2 = 70.5 → rounds to 71
      expect(ProgressRepository.computeReadiness([70, 71]), 71);
    });

    test('clamps to 100 maximum', () {
      expect(ProgressRepository.computeReadiness([100, 100]), 100);
    });

    test('clamps to 0 minimum', () {
      expect(ProgressRepository.computeReadiness([0, 0]), 0);
    });

    test('averages correctly across 10 sessions', () {
      final scores = List.filled(10, 60);
      expect(ProgressRepository.computeReadiness(scores), 60);
    });
  });

  // ── computeSectionTrends ────────────────────────────────────────────────────

  group('computeSectionTrends', () {
    test('returns empty list for empty sessions', () {
      expect(ProgressRepository.computeSectionTrends([]), isEmpty);
    });

    test('computes accuracy for a single section', () {
      // 2 correct out of 3 = 66.67% → rounds to 67
      final sessions = [
        _session({'PA': [true, false, true]}),
      ];
      final trends = ProgressRepository.computeSectionTrends(sessions);
      expect(trends.length, 1);
      expect(trends.first.section, 'PA');
      expect(trends.first.currentAccuracy, 67);
    });

    test('delta is zero when no previous window exists', () {
      final sessions = List.generate(
        3,
        (_) => _session({'PA': [true]}),
      );
      final trends = ProgressRepository.computeSectionTrends(sessions);
      expect(trends.single.delta, 0);
    });

    test('delta is positive when recent window outperforms previous', () {
      // recent (first 5): all correct = 100%
      // previous (next 5): all wrong = 0%  → delta = +100
      final sessions = [
        ...List.generate(5, (_) => _session({'PA': [true]})),
        ...List.generate(5, (_) => _session({'PA': [false]})),
      ];
      final trends = ProgressRepository.computeSectionTrends(sessions);
      expect(trends.single.delta, greaterThan(0));
    });

    test('delta is negative when recent window underperforms previous', () {
      // recent (first 5): all wrong = 0%
      // previous (next 5): all correct = 100% → delta = -100
      final sessions = [
        ...List.generate(5, (_) => _session({'PA': [false]})),
        ...List.generate(5, (_) => _session({'PA': [true]})),
      ];
      final trends = ProgressRepository.computeSectionTrends(sessions);
      expect(trends.single.delta, lessThan(0));
    });

    test('returns at most 4 sections', () {
      final session = _session({
        'A': [true, true],
        'B': [false, false],
        'C': [true, false],
        'D': [true, true, false],
        'E': [false],
      });
      final trends = ProgressRepository.computeSectionTrends([session]);
      expect(trends.length, 4);
    });

    test('results are sorted ascending by currentAccuracy', () {
      final session = _session({
        'High':   [true, true, true],   // 100%
        'Low':    [false, false],        // 0%
        'Medium': [true, false],         // 50%
      });
      final trends = ProgressRepository.computeSectionTrends([session]);
      for (var i = 0; i < trends.length - 1; i++) {
        expect(
          trends[i].currentAccuracy,
          lessThanOrEqualTo(trends[i + 1].currentAccuracy),
        );
      }
    });

    test('handles sessions with no questionResults gracefully', () {
      final sessions = [
        {'questionResults': null},
        {'questionResults': 'bad data'},
        _session({'PA': [true]}),
      ];
      final trends = ProgressRepository.computeSectionTrends(sessions);
      expect(trends.single.section, 'PA');
      expect(trends.single.currentAccuracy, 100);
    });

    test('accumulates results across multiple sessions for the same section', () {
      // 3 sessions × 1 correct each = 3/3 = 100%
      final sessions = List.generate(
        3,
        (_) => _session({'SS': [true]}),
      );
      final trends = ProgressRepository.computeSectionTrends(sessions);
      expect(trends.single.currentAccuracy, 100);
    });
  });
}
