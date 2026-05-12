import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

const int kReadinessPassThreshold = 70;
const int kReadinessPracticeThreshold = 40;

const String kAppVersion = '1.0.0';

Color readinessColor(int percent) {
  if (percent >= kReadinessPassThreshold) return AppTheme.success;
  if (percent >= kReadinessPracticeThreshold) return AppTheme.warning;
  return AppTheme.error;
}

String readinessLabel(int percent) {
  if (percent >= kReadinessPassThreshold) return 'On track for the exam';
  if (percent >= kReadinessPracticeThreshold) return 'Keep practicing';
  return 'Just getting started';
}

String resultLabel(int score) {
  if (score >= kReadinessPassThreshold) return 'Passing — great work!';
  if (score >= 50) return 'Almost there — keep studying';
  return 'Needs more practice';
}
