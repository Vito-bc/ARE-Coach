import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
      appBar: AppBar(title: const Text('Attempt History')),
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          FutureBuilder<List<AttemptHistoryItem>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final items = snapshot.data ?? const <AttemptHistoryItem>[];
              if (items.isEmpty) {
                return const Center(
                  child: Text('No attempt history yet. Complete a test to see trends.'),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return AppGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Score: ${item.score}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                              const Spacer(),
                              Text(_formatDate(item.endedAt)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Mode: ${item.mode}'),
                          Text('Correct: ${item.correctCount}/${item.questionCount}'),
                          Text('Time: ${_formatDuration(item.timeSpentSec)}'),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$mm/$dd ${dt.year} $hh:$min';
  }

  String _formatDuration(int sec) {
    final min = (sec ~/ 60).toString().padLeft(2, '0');
    final rem = (sec % 60).toString().padLeft(2, '0');
    return '$min:$rem';
  }
}
