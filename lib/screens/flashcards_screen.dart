import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/flashcard.dart';
import '../services/flashcard_repository.dart';
import 'flashcard_session_screen.dart';

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  final _repo = FlashcardRepository();
  bool _loading = true;
  Map<String, List<Flashcard>> _sections = {};
  Map<String, CardStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = await _repo.loadAll();
    final statuses = await _repo.allStatuses();
    final sections = <String, List<Flashcard>>{};
    for (final c in cards) {
      sections.putIfAbsent(c.section, () => []).add(c);
    }
    if (mounted) {
      setState(() {
        _sections = sections;
        _statuses = statuses;
        _loading = false;
      });
    }
  }

  int _masteredCount(List<Flashcard> cards) =>
      cards.where((c) => _statuses[c.id] == CardStatus.mastered).length;

  int _totalMastered() =>
      _statuses.values.where((s) => s == CardStatus.mastered).length;

  int _totalCards() => _statuses.length;

  Future<void> _openSection(String section, List<Flashcard> cards) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlashcardSessionScreen(
          section: section,
          cards: cards,
          initialStatuses: Map.fromEntries(
            cards.map((c) => MapEntry(c.id, _statuses[c.id] ?? CardStatus.fresh)),
          ),
          onComplete: (updated) {
            setState(() => _statuses.addAll(updated));
          },
        ),
      ),
    );
    final statuses = await _repo.allStatuses();
    if (mounted) setState(() => _statuses = statuses);
  }

  @override
  Widget build(BuildContext context) {
    final totalMastered = _totalMastered();
    final totalCards = _totalCards();

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/FlashCardsBackgoundP.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          // Dark gradient overlay for readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    AppTheme.navy.withValues(alpha: 0.80),
                    AppTheme.navy.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: _loading
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
              slivers: [
                // ── Hero header ──────────────────────────────────
                SliverToBoxAdapter(
                  child: _HeroSection(
                    totalCards: totalCards,
                    mastered: totalMastered,
                  ),
                ),

                // ── Stats row ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    child: _StatsRow(
                      mastered: totalMastered,
                      learning: _statuses.values
                          .where((s) => s == CardStatus.learning)
                          .length,
                      fresh: _statuses.values
                          .where((s) => s == CardStatus.fresh)
                          .length,
                      total: totalCards,
                    ),
                  ),
                ),

                // ── Section label ────────────────────────────────
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'ARE 5.0 DIVISIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),

                // ── Deck cards ───────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final entry = _sections.entries.elementAt(i);
                        return _DeckCard(
                          section: entry.key,
                          cards: entry.value,
                          mastered: _masteredCount(entry.value),
                          onTap: () => _openSection(entry.key, entry.value),
                        );
                      },
                      childCount: _sections.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.totalCards, required this.mastered});

  final int totalCards;
  final int mastered;

  @override
  Widget build(BuildContext context) {
    final pct = totalCards == 0 ? 0.0 : mastered / totalCards;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.yellow.withValues(alpha: 0.12),
            AppTheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.yellow.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.yellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, size: 12, color: AppTheme.yellow),
                SizedBox(width: 5),
                Text(
                  'ARE 5.0 · All 6 Divisions',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.yellow,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          const Text(
            'Flash­Cards',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Exam-focused cards built around NCARB\'s published content outlines. Each card targets a term, code, or concept that appears on the ARE — with the code reference and an exam tip on the back.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),

          // Progress bar + label
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$mastered of $totalCards mastered',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '${(pct * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.yellow,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: AppTheme.separator,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.yellow),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // How it works chips
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HowChip(icon: Icons.touch_app_rounded, label: 'Tap to flip'),
              _HowChip(icon: Icons.check_circle_outline_rounded, label: 'Rate yourself'),
              _HowChip(icon: Icons.trending_up_rounded, label: 'Track mastery'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HowChip extends StatelessWidget {
  const _HowChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.mastered,
    required this.learning,
    required this.fresh,
    required this.total,
  });

  final int mastered;
  final int learning;
  final int fresh;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(value: '$mastered', label: 'Mastered', color: AppTheme.success),
        const SizedBox(width: 8),
        _StatChip(value: '$learning', label: 'Learning', color: AppTheme.warning),
        const SizedBox(width: 8),
        _StatChip(value: '$fresh', label: 'New', color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        _StatChip(value: '$total', label: 'Total', color: AppTheme.blue),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Deck card ─────────────────────────────────────────────────────────────────

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.section,
    required this.cards,
    required this.mastered,
    required this.onTap,
  });

  final String section;
  final List<Flashcard> cards;
  final int mastered;
  final VoidCallback onTap;

  static const _sectionMeta = {
    'Practice Management':        (Icons.business_center_rounded,     'PcM'),
    'Project Management':         (Icons.account_tree_rounded,        'PjM'),
    'Programming & Analysis':     (Icons.grid_view_rounded,           'PA'),
    'Project Planning & Design':  (Icons.architecture_rounded,        'PPD'),
    'Project Docs & Delivery':    (Icons.description_rounded,         'PDD'),
    'Construction & Evaluation':  (Icons.construction_rounded,        'CE'),
    'NYC Building Codes':         (Icons.location_city_rounded,       'NYC'),
  };

  @override
  Widget build(BuildContext context) {
    final total = cards.length;
    final pct = total == 0 ? 0.0 : mastered / total;
    final meta = _sectionMeta[section] ?? (Icons.style_rounded, '—');
    final icon = meta.$1;
    final abbr = meta.$2;

    final isDone = mastered == total;
    final hasStarted = mastered > 0;

    final statusLabel = isDone
        ? 'Complete ✓'
        : hasStarted
            ? '$mastered / $total mastered'
            : '$total cards · not started';

    final statusColor = isDone
        ? AppTheme.success
        : hasStarted
            ? AppTheme.yellow
            : AppTheme.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDone
                ? AppTheme.success.withValues(alpha: 0.3)
                : AppTheme.separator,
            width: isDone ? 1 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Ring + icon
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    backgroundColor: AppTheme.separator,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDone ? AppTheme.success : AppTheme.yellow,
                    ),
                  ),
                  Center(
                    child: Icon(
                      icon,
                      size: 22,
                      color: isDone ? AppTheme.success : AppTheme.yellow,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.yellow.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          abbr,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.yellow,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          section,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(fontSize: 11, color: statusColor),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 3,
                      backgroundColor: AppTheme.separator,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDone ? AppTheme.success : AppTheme.yellow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
