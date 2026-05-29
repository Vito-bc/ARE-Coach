import 'package:hive_flutter/hive_flutter.dart';

/// Manages the daily study streak stored in Hive.
///
/// Call [recordToday] once per completed study session (quiz or flashcards).
/// Call [read] to display the current streak count without modifying it.
class StudyStreak {
  static const _boxName = 'settings';
  static const _streakKey = 'studyStreak';
  static const _dateKey = 'lastStudyDate';

  /// Records today as a study day and updates the streak.
  /// Safe to call multiple times — only counts once per calendar day.
  static Future<void> recordToday() async {
    final box = await Hive.openBox(_boxName);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastDate = box.get(_dateKey) as String?;

    if (lastDate == today) return; // already recorded today

    final stored = box.get(_streakKey, defaultValue: 0) as int;
    final last = lastDate != null ? DateTime.tryParse(lastDate) : null;
    final daysSinceLast = last != null
        ? DateTime.now().difference(last).inDays
        : 999;
    final newStreak = daysSinceLast == 1 ? stored + 1 : 1;

    await box.put(_streakKey, newStreak);
    await box.put(_dateKey, today);
  }

  /// Returns the current streak without modifying it.
  static Future<int> read() async {
    final box = await Hive.openBox(_boxName);
    return box.get(_streakKey, defaultValue: 0) as int;
  }
}
