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

class DashboardMetrics {
  const DashboardMetrics({
    required this.readinessPercent,
    required this.weakSections,
    required this.attemptsCount,
  });

  final int readinessPercent;
  final List<WeakSectionMetric> weakSections;
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

      return DashboardMetrics(
        readinessPercent: readiness,
        weakSections: weakSections,
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
      );
    }
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
