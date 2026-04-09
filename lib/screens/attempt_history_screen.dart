import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/progress_repository.dart';

class AttemptHistoryScreen extends StatefulWidget {
  const AttemptHistoryScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<AttemptHistoryScreen> createState() => _AttemptHistoryScreenState();
}

class _AttemptHistoryScreenState extends State<AttemptHistoryScreen> {
  final _progressRepository = ProgressRepository();
  late final Future<List<AttemptHistoryItem>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<AttemptHistoryItem>> _loadHistory() async {
    if (!widget.firebaseReady) {
      return _progressRepository.fetchAttemptHistory(uid: 'demo-user');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    return _progressRepository.fetchAttemptHistory(uid: uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        title: const Text('Attempt History'),
        backgroundColor: AppTheme.navy,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: FutureBuilder<List<AttemptHistoryItem>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.yellow),
            );
          }

          final items = snapshot.data ?? const <AttemptHistoryItem>[];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No attempt history yet.\nComplete a test to see your trends.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, height: 1.6),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final scoreColor = item.score >= 70
                  ? AppTheme.success
                  : item.score >= 50
                      ? AppTheme.warning
                      : AppTheme.error;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.separator, width: 0.5),
                ),
                child: Row(
                  children: [
                    // Score circle
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scoreColor.withValues(alpha: 0.1),
                        border: Border.all(
                          color: scoreColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${item.score}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: scoreColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _modeLabel(item.mode),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatDate(item.endedAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _Pill(
                                '${item.correctCount}/${item.questionCount} correct',
                                AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              _Pill(
                                _formatDuration(item.timeSpentSec),
                                AppTheme.textSecondary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'quick':
        return 'Quick Quiz';
      case 'timed':
        return 'Timed Exam';
      case 'section':
        return 'By Division';
      default:
        return mode[0].toUpperCase() + mode.substring(1);
    }
  }

  String _formatDate(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$mm/$dd ${dt.year}';
  }

  String _formatDuration(int sec) {
    final min = (sec ~/ 60).toString().padLeft(2, '0');
    final rem = (sec % 60).toString().padLeft(2, '0');
    return '$min:$rem';
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}
