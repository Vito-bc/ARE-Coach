import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// Our internal practice target. NOT an NCARB passing score: the real ARE is
/// scored per division against NCARB's published ranges (58-71% depending on
/// the division) and reported only as pass/fail. Never label a score here as
/// "passing".
const int kPracticeTarget = 70;
const int kReadinessPracticeThreshold = 40;

Color readinessColor(int percent) {
  if (percent >= kPracticeTarget) return AppTheme.success;
  if (percent >= kReadinessPracticeThreshold) return AppTheme.warning;
  return AppTheme.error;
}

String readinessLabel(int percent) {
  if (percent >= kPracticeTarget) return 'On track for the exam';
  if (percent >= kReadinessPracticeThreshold) return 'Keep practicing';
  return 'Just getting started';
}

String resultLabel(int score) {
  if (score >= kPracticeTarget) return 'Above your practice target';
  if (score >= 50) return 'Almost there — keep studying';
  return 'Needs more practice';
}
