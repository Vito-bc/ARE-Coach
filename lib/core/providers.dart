import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/quiz_question.dart';
import '../services/progress_repository.dart';
import '../services/question_repository.dart';

typedef DashboardArgs = ({String? uid, bool firebaseReady});

/// App version read from the platform package metadata, so it can never drift
/// out of sync with pubspec.yaml the way a hardcoded constant did.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Shared dashboard metrics — used by both DashboardScreen and ProfileScreen.
/// Not auto-disposed so the cache survives tab switches.
/// Invalidate via ref.invalidate(dashboardMetricsProvider) after saving an attempt.
final dashboardMetricsProvider =
    FutureProvider.family<DashboardMetrics, DashboardArgs>((ref, args) async {
  // No backend (local/dev mode, or Firebase failed to init): report NO data
  // rather than fabricated progress. The dashboard has an honest empty state.
  // Never show a readiness number we did not actually measure.
  if (!args.firebaseReady) {
    return const DashboardMetrics(
      readinessPercent: 0,
      attemptsCount: 0,
      weakSections: [],
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

/// Last N attempt scores (oldest first) for the sparkline chart.
final recentScoresProvider =
    FutureProvider.family<List<ScorePoint>, DashboardArgs>((ref, args) async {
  if (!args.firebaseReady || args.uid == null) return [];
  return ProgressRepository().fetchRecentScores(uid: args.uid!);
});

/// All section accuracies ordered lowest→highest for the Insights screen.
final allSectionAccuraciesProvider =
    FutureProvider.family<List<WeakSectionMetric>, DashboardArgs>(
        (ref, args) async {
  if (!args.firebaseReady || args.uid == null) return [];
  return ProgressRepository().fetchAllSectionAccuracies(uid: args.uid!);
});

/// Streams the user's role ('free' | 'premium') directly from Firestore.
/// Auto-updates when validateReceipt writes role: 'premium' server-side.
final userRoleProvider = StreamProvider.family<String, String?>((ref, uid) {
  if (uid == null) return Stream.value('free');
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) => (snap.data()?['role'] as String?) ?? 'free');
});
