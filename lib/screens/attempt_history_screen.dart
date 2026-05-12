import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/ui/app_chrome.dart';
import '../services/progress_repository.dart';

class AttemptHistoryScreen extends StatefulWidget {
  const AttemptHistoryScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<AttemptHistoryScreen> createState() => _AttemptHistoryScreenState();
}

class _AttemptHistoryScreenState extends State<AttemptHistoryScreen> {
  final _progressRepository = ProgressRepository();
  final _items = <AttemptHistoryItem>[];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  QueryDocumentSnapshot<Map<String, dynamic>>? _cursor;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _loadPage();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _cursor = page.cursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load history. Check your connection.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _loadPage(startAfter: _cursor);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _cursor = page.cursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load more. Try again.')),
      );
    }
  }

  Future<AttemptHistoryPage> _loadPage({
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    if (!widget.firebaseReady) {
      return _progressRepository.fetchAttemptHistoryPage(
        uid: 'demo-user',
        limit: 20,
        startAfter: startAfter,
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const AttemptHistoryPage(items: [], hasMore: false);
    }

    return _progressRepository.fetchAttemptHistoryPage(
      uid: uid,
      limit: 20,
      startAfter: startAfter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        title: const Text('Attempt History'),
        backgroundColor: AppTheme.navy.withValues(alpha: 0.92),
        foregroundColor: AppTheme.textPrimary,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.yellow),
                )
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          size: 40,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadInitial,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No attempt history yet.\nComplete a test to see your trends.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary, height: 1.6),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    ..._items.map(_buildHistoryCard),
                    if (_hasMore) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: OutlinedButton(
                          onPressed: _loadingMore ? null : _loadMore,
                          child: Text(_loadingMore ? 'Loading...' : 'Load more'),
                        ),
                      ),
                    ],
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(AttemptHistoryItem item) {
    final scoreColor = item.score >= 70
        ? AppTheme.success
        : item.score >= 50
        ? AppTheme.warning
        : AppTheme.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: Row(
        children: [
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
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
