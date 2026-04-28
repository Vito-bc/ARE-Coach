import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quiz_question.dart';
import '../services/progress_repository.dart';
import '../services/question_repository.dart';

typedef DashboardArgs = ({String? uid, bool firebaseReady});

/// Shared dashboard metrics — used by both DashboardScreen and ProfileScreen.
/// Not auto-disposed so the cache survives tab switches.
/// Invalidate via ref.invalidate(dashboardMetricsProvider) after saving an attempt.
final dashboardMetricsProvider =
    FutureProvider.family<DashboardMetrics, DashboardArgs>((ref, args) async {
  if (!args.firebaseReady) {
    return const DashboardMetrics(
      readinessPercent: 42,
      attemptsCount: 3,
      weakSections: [
        WeakSectionMetric(section: 'Project Management', accuracy: 31),
        WeakSectionMetric(section: 'Programming & Analysis', accuracy: 38),
        WeakSectionMetric(section: 'Structural Systems', accuracy: 43),
      ],
      sectionTrends: [],
    );
  }
  final uid = args.uid;
  if (uid == null) {
    return const DashboardMetrics(
      readinessPercent: 0,
      attemptsCount: 0,
      weakSections: [],
      sectionTrends: [],
    );
  }
  return ProgressRepository().fetchDashboardMetrics(uid: uid);
});

/// All questions loaded once and cached for the app session.
/// TestsScreen filters/shuffles client-side so re-starting a test is instant.
final allQuestionsProvider = FutureProvider<List<QuizQuestion>>((ref) {
  return QuestionRepository().loadFromAsset(limit: 0);
});
