import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/study_streak.dart';
import '../core/theme/app_theme.dart';
import '../models/flashcard.dart';
import '../services/flashcard_repository.dart';
import '../services/iap_service.dart';
import 'coach_screen.dart';
import 'paywall_screen.dart';

class FlashcardSessionScreen extends ConsumerStatefulWidget {
  const FlashcardSessionScreen({
    super.key,
    required this.section,
    required this.cards,
    required this.initialStatuses,
    required this.onComplete,
  });

  final String section;
  final List<Flashcard> cards;
  final Map<String, CardStatus> initialStatuses;
  final void Function(Map<String, CardStatus> updated) onComplete;

  @override
  ConsumerState<FlashcardSessionScreen> createState() =>
      _FlashcardSessionScreenState();
}

class _FlashcardSessionScreenState extends ConsumerState<FlashcardSessionScreen>
    with SingleTickerProviderStateMixin {
  final _repo = FlashcardRepository();
  late final AnimationController _flipCtrl;
  late final Animation<double> _flipAnim;

  List<Flashcard> _queue = [];
  late Map<String, CardStatus> _statuses;

  int _index = 0;
  bool _showBack = false;
  bool _done = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _statuses = Map.of(widget.initialStatuses);
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _flipAnim = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut),
    );
    _initQueue();
  }

  Future<void> _initQueue() async {
    final sorted = await _repo.sortedForSession(widget.cards);
    if (mounted) {
      setState(() {
        _queue = sorted;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  Flashcard get _current => _queue[_index];

  Future<void> _flip() async {
    await HapticFeedback.selectionClick();
    if (_showBack) {
      await _flipCtrl.reverse();
    } else {
      await _flipCtrl.forward();
    }
    setState(() => _showBack = !_showBack);
  }

  Future<void> _rate(CardStatus status) async {
    await HapticFeedback.lightImpact();
    _statuses[_current.id] = status;
    await _repo.setStatus(_current.id, status);

    if (_index < _queue.length - 1) {
      // Reset card to front
      _flipCtrl.reset();
      setState(() {
        _showBack = false;
        _index++;
      });
    } else {
      await StudyStreak.recordToday();
      widget.onComplete(_statuses);
      setState(() => _done = true);
    }
  }

  /// Premium: open the AI Coach pre-filled with a "explain this card" prompt.
  /// Free: a gentle upgrade prompt that leads to the paywall.
  void _explainWithCoach() {
    final card = _current;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final role = ref.read(userRoleProvider(uid)).valueOrNull ?? 'free';
    final isPremium = role == 'premium';

    if (!isPremium) {
      unawaited(_showCoachUpsell());
      return;
    }

    final prompt =
        'Explain this ARE flashcard in simpler terms, then give one short '
        'practical example.\n\nTerm: ${card.front}\nDefinition: ${card.back}';
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CoachScreen(initialMessage: prompt)),
    );
  }

  Future<void> _showCoachUpsell() async {
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Ask the Coach',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'Get this card explained in plain language with an example by the AI '
          'Coach. Available on Premium.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Maybe later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
    if (upgrade == true && mounted) {
      unawaited(Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PaywallScreen(iapService: IAPService())),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        foregroundColor: AppTheme.textPrimary,
        title: Text(widget.section),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_index + 1} / ${_queue.length}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _done ? _Summary(statuses: _statuses, cards: widget.cards) : _Session(
        current: _current,
        index: _index,
        total: _queue.length,
        flipAnim: _flipAnim,
        showBack: _showBack,
        onFlip: _flip,
        onRate: _rate,
        onExplain: _explainWithCoach,
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Session body
// ──────────────────────────────────────────────

class _Session extends StatelessWidget {
  const _Session({
    required this.current,
    required this.index,
    required this.total,
    required this.flipAnim,
    required this.showBack,
    required this.onFlip,
    required this.onRate,
    required this.onExplain,
  });

  final Flashcard current;
  final int index;
  final int total;
  final Animation<double> flipAnim;
  final bool showBack;
  final VoidCallback onFlip;
  final void Function(CardStatus) onRate;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Progress bar
        LinearProgressIndicator(
          value: (index + 1) / total,
          minHeight: 3,
          backgroundColor: AppTheme.separator,
          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.yellow),
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            child: Column(
              children: [
                // Tap hint
                AnimatedOpacity(
                  opacity: showBack ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: const Text(
                    'Tap card to reveal',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),

                // Flip card
                Expanded(
                  child: GestureDetector(
                    onTap: onFlip,
                    child: AnimatedBuilder(
                      animation: flipAnim,
                      builder: (_, __) {
                        final angle = flipAnim.value;
                        // Front: 0→π/2 visible, Back: π/2→π visible
                        final showingFront = angle < math.pi / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: showingFront
                              ? _CardFace(
                                  label: 'TERM',
                                  content: current.front,
                                  codeRef: null,
                                  examTip: null,
                                  isBack: false,
                                )
                              : Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()..rotateY(math.pi),
                                  child: _CardFace(
                                    label: 'DEFINITION',
                                    content: current.back,
                                    codeRef: current.codeRef,
                                    examTip: current.examTip,
                                    isBack: true,
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Explain with Coach — only visible after flip
                AnimatedOpacity(
                  opacity: showBack ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !showBack,
                    child: _ExplainButton(onTap: onExplain),
                  ),
                ),

                const SizedBox(height: 12),

                // Rating row — only visible after flip
                AnimatedOpacity(
                  opacity: showBack ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !showBack,
                    child: _RatingRow(onRate: onRate),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExplainButton extends StatelessWidget {
  const _ExplainButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.blue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.blue.withValues(alpha: 0.35)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.blue),
            SizedBox(width: 8),
            Text(
              'Explain with Coach',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.label,
    required this.content,
    required this.codeRef,
    required this.examTip,
    required this.isBack,
  });

  final String label;
  final String content;
  final String? codeRef;
  final String? examTip;
  final bool isBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isBack
              ? AppTheme.yellow.withValues(alpha: 0.25)
              : AppTheme.separator,
          width: isBack ? 1.5 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: isBack ? AppTheme.yellow : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              content,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                height: 1.5,
                letterSpacing: -0.3,
              ),
            ),
            if (codeRef != null && codeRef!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.yellow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  codeRef!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.yellow,
                  ),
                ),
              ),
            ],
            if (examTip != null && examTip!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      examTip!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.onRate});

  final void Function(CardStatus) onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RatingButton(
            label: 'Again',
            icon: Icons.close_rounded,
            color: AppTheme.error,
            onTap: () => onRate(CardStatus.fresh),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RatingButton(
            label: 'Not sure',
            icon: Icons.remove_rounded,
            color: AppTheme.warning,
            onTap: () => onRate(CardStatus.learning),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RatingButton(
            label: 'Got it',
            icon: Icons.check_rounded,
            color: AppTheme.success,
            onTap: () => onRate(CardStatus.mastered),
          ),
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Summary screen shown after last card
// ──────────────────────────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({required this.statuses, required this.cards});

  final Map<String, CardStatus> statuses;
  final List<Flashcard> cards;

  @override
  Widget build(BuildContext context) {
    final mastered = cards.where((c) => statuses[c.id] == CardStatus.mastered).length;
    final learning = cards.where((c) => statuses[c.id] == CardStatus.learning).length;
    final fresh = cards.where((c) => statuses[c.id] == CardStatus.fresh).length;
    final total = cards.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 40,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Session Complete!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You reviewed $total cards',
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _SummaryTile(count: mastered, label: 'Mastered', color: AppTheme.success),
              const SizedBox(width: 10),
              _SummaryTile(count: learning, label: 'Learning', color: AppTheme.warning),
              const SizedBox(width: 10),
              _SummaryTile(count: fresh, label: 'Again', color: AppTheme.error),
            ],
          ),
          const SizedBox(height: 36),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Decks'),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
