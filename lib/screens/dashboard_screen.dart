import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/progress_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _progressRepository = ProgressRepository();
  late final Future<DashboardMetrics> _metricsFuture;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
  }

  Future<DashboardMetrics> _loadMetrics() async {
    if (!widget.firebaseReady) {
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const DashboardMetrics(
        readinessPercent: 42,
        attemptsCount: 0,
        weakSections: [],
      );
    }
    return _progressRepository.fetchDashboardMetrics(uid: uid);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<DashboardMetrics>(
        future: _metricsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final metrics = snapshot.data ??
              const DashboardMetrics(
                readinessPercent: 42,
                attemptsCount: 0,
                weakSections: [],
              );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'NYC ARE Dashboard',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text(widget.firebaseReady ? 'Backend connected' : 'Demo mode'),
                  avatar: Icon(
                    widget.firebaseReady
                        ? Icons.cloud_done_outlined
                        : Icons.play_circle_outline,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 90,
                        width: 90,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: (metrics.readinessPercent / 100).clamp(0, 1),
                              strokeWidth: 10,
                              backgroundColor: Colors.grey.shade200,
                            ),
                            Center(
                              child: Text(
                                '${metrics.readinessPercent}%',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'You are ${metrics.readinessPercent}% ready.\nRecent attempts: ${metrics.attemptsCount}.',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weak Sections',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      if (metrics.weakSections.isEmpty)
                        const Text('No attempts yet. Complete one test to unlock analytics.')
                      else
                        ...metrics.weakSections
                            .map((m) => _weakRow(m.section, m.accuracy)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '90-second Demo',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Shows adaptive question, code citation, and weak-topic recommendation.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Demo flow: Dashboard -> Test insight -> Coach explanation',
                              ),
                            ),
                          );
                        },
                        child: const Text('Play Product Demo'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Today Plan'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.mic),
                label: const Text('Talk to Coach'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _weakRow(String label, int score) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$score%'),
        ],
      ),
    );
  }
}
