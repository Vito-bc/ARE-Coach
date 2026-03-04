import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/quiz_question.dart';

class WeakSectionMetric {
  const WeakSectionMetric({
    required this.section,
    required this.accuracy,
  });

  final String section;
  final int accuracy;
}

class SectionTrendMetric {
  const SectionTrendMetric({
    required this.section,
    required this.currentAccuracy,
    required this.delta,
  });

  final String section;
  final int currentAccuracy;
  final int delta;
}

class AttemptHistoryItem {
  const AttemptHistoryItem({
    required this.id,
    required this.mode,
    required this.score,
    required this.questionCount,
    required this.correctCount,
    required this.timeSpentSec,
    required this.endedAt,
  });

  final String id;
  final String mode;
  final int score;
  final int questionCount;
  final int correctCount;
  final int timeSpentSec;
  final DateTime endedAt;
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.readinessPercent,
    required this.weakSections,
    required this.sectionTrends,
    required this.attemptsCount,
  });

  final int readinessPercent;
  final List<WeakSectionMetric> weakSections;
  final List<SectionTrendMetric> sectionTrends;
  final int attemptsCount;
}

class ProgressRepository {
  ProgressRepository({FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore => _providedFirestore ?? FirebaseFirestore.instance;

  Future<void> saveAttempt({
    required String uid,
    required List<QuizQuestion> questions,
    required Map<String, String> answersByQuestionId,
    required int timeSpentSec,
    required String mode,
  }) async {
    final sessionsRef = _firestore.collection('attempts').doc(uid).collection('sessions');
    final weakRef = _firestore.collection('analytics').doc(uid).collection('weakTopics');
    final todayRef = _firestore
        .collection('usage')
        .doc(uid)
        .collection('daily')
        .doc(_todayKey());

    var correctCount = 0;
    final results = <Map<String, dynamic>>[];

    for (final q in questions) {
      final selected = answersByQuestionId[q.id];
      final isCorrect = selected == q.correctOption;
      if (isCorrect) correctCount++;

      results.add({
        'questionId': q.id,
        'section': q.section,
        'selected': selected ?? '',
        'correctOption': q.correctOption,
        'isCorrect': isCorrect,
      });

      final weakTopicDoc = weakRef.doc(_normalizeSection(q.section));
      await _firestore.runTransaction((txn) async {
        final snapshot = await txn.get(weakTopicDoc);
        final previousTotal = (snapshot.data()?['total'] as num?)?.toInt() ?? 0;
        final previousCorrect = (snapshot.data()?['correct'] as num?)?.toInt() ?? 0;
        final total = previousTotal + 1;
        final correct = previousCorrect + (isCorrect ? 1 : 0);
        final accuracy = total == 0 ? 0 : ((correct / total) * 100).round();
        txn.set(weakTopicDoc, {
          'section': q.section,
          'total': total,
          'correct': correct,
          'wrongCount': total - correct,
          'accuracy': accuracy,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'trend': 'steady',
        }, SetOptions(merge: true));
      });
    }

    final scorePercent =
        questions.isEmpty ? 0 : ((correctCount / questions.length) * 100).round();

    await sessionsRef.add({
      'mode': mode,
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': FieldValue.serverTimestamp(),
      'score': scorePercent,
      'timeSpentSec': timeSpentSec,
      'questionCount': questions.length,
      'correctCount': correctCount,
      'questionResults': results,
    });

    await todayRef.set({
      'questionsUsed': FieldValue.increment(questions.length),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DashboardMetrics> fetchDashboardMetrics({
    required String uid,
  }) async {
    try {
      final sessionsQuery = await _firestore
          .collection('attempts')
          .doc(uid)
          .collection('sessions')
          .orderBy('endedAt', descending: true)
          .limit(10)
          .get();

      var readiness = 42;
      if (sessionsQuery.docs.isNotEmpty) {
        final scores = sessionsQuery.docs
            .map((doc) => (doc.data()['score'] as num?)?.toInt() ?? 0)
            .toList();
        final avg = scores.reduce((a, b) => a + b) / scores.length;
        readiness = avg.round().clamp(0, 100);
      }

      final weakTopicsQuery = await _firestore
          .collection('analytics')
          .doc(uid)
          .collection('weakTopics')
          .orderBy('accuracy')
          .limit(3)
          .get();

      final weakSections = weakTopicsQuery.docs.map((doc) {
        final data = doc.data();
        return WeakSectionMetric(
          section: data['section']?.toString() ?? doc.id,
          accuracy: (data['accuracy'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      final trends = _computeSectionTrends(
        sessionsQuery.docs.map((d) => d.data()).toList(),
      );

      return DashboardMetrics(
        readinessPercent: readiness,
        weakSections: weakSections,
        sectionTrends: trends,
        attemptsCount: sessionsQuery.docs.length,
      );
    } catch (_) {
      return const DashboardMetrics(
        readinessPercent: 42,
        attemptsCount: 0,
        weakSections: [
          WeakSectionMetric(section: 'Project Management', accuracy: 31),
          WeakSectionMetric(section: 'Programming & Analysis', accuracy: 38),
          WeakSectionMetric(section: 'Structural Systems', accuracy: 43),
        ],
        sectionTrends: [
          SectionTrendMetric(section: 'Project Management', currentAccuracy: 52, delta: 8),
          SectionTrendMetric(
            section: 'Programming & Analysis',
            currentAccuracy: 47,
            delta: -5,
          ),
          SectionTrendMetric(section: 'Structural Systems', currentAccuracy: 61, delta: 4),
        ],
      );
    }
  }

  Future<List<AttemptHistoryItem>> fetchAttemptHistory({
    required String uid,
    int limit = 20,
  }) async {
    try {
      final query = await _firestore
          .collection('attempts')
          .doc(uid)
          .collection('sessions')
          .orderBy('endedAt', descending: true)
          .limit(limit)
          .get();

      return query.docs.map((doc) {
        final data = doc.data();
        final ts = data['endedAt'];
        DateTime endedAt = DateTime.now();
        if (ts is Timestamp) {
          endedAt = ts.toDate();
        } else if (ts is String) {
          endedAt = DateTime.tryParse(ts) ?? DateTime.now();
        }

        return AttemptHistoryItem(
          id: doc.id,
          mode: data['mode']?.toString() ?? 'section',
          score: (data['score'] as num?)?.toInt() ?? 0,
          questionCount: (data['questionCount'] as num?)?.toInt() ?? 0,
          correctCount: (data['correctCount'] as num?)?.toInt() ?? 0,
          timeSpentSec: (data['timeSpentSec'] as num?)?.toInt() ?? 0,
          endedAt: endedAt,
        );
      }).toList();
    } catch (_) {
      return List.generate(
        5,
        (i) => AttemptHistoryItem(
          id: 'demo_$i',
          mode: 'section',
          score: 55 + (i * 6),
          questionCount: 5,
          correctCount: 3 + (i % 2),
          timeSpentSec: 220 + (i * 35),
          endedAt: DateTime.now().subtract(Duration(days: i)),
        ),
      );
    }
  }

  List<SectionTrendMetric> _computeSectionTrends(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) {
      return const [];
    }

    final recentWindow = sessions.take(5).toList();
    final previousWindow = sessions.skip(5).take(5).toList();

    final recentStats = _accumulateSectionStats(recentWindow);
    final previousStats = _accumulateSectionStats(previousWindow);

    final trends = <SectionTrendMetric>[];
    for (final entry in recentStats.entries) {
      final section = entry.key;
      final recent = entry.value;
      final prev = previousStats[section];
      final currentAccuracy = recent.total == 0 ? 0 : ((recent.correct / recent.total) * 100).round();
      final previousAccuracy = (prev == null || prev.total == 0)
          ? currentAccuracy
          : ((prev.correct / prev.total) * 100).round();
      trends.add(
        SectionTrendMetric(
          section: section,
          currentAccuracy: currentAccuracy,
          delta: currentAccuracy - previousAccuracy,
        ),
      );
    }

    trends.sort((a, b) => a.currentAccuracy.compareTo(b.currentAccuracy));
    return trends.take(4).toList();
  }

  Map<String, _SectionStats> _accumulateSectionStats(List<Map<String, dynamic>> sessions) {
    final map = <String, _SectionStats>{};
    for (final session in sessions) {
      final results = session['questionResults'];
      if (results is! List<dynamic>) continue;

      for (final raw in results) {
        if (raw is! Map<String, dynamic>) continue;
        final section = raw['section']?.toString() ?? 'Unknown';
        final isCorrect = raw['isCorrect'] == true;
        final stats = map.putIfAbsent(section, () => _SectionStats());
        stats.total += 1;
        if (isCorrect) stats.correct += 1;
      }
    }
    return map;
  }

  String _todayKey() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}_${mm}_$dd';
  }

  String _normalizeSection(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }
}

class _SectionStats {
  int total = 0;
  int correct = 0;
}
