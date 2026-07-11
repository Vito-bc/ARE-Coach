import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../core/ui/app_chrome.dart';

// Official NCARB-published passing ranges: the share of SCORED items you must
// answer correctly to pass. The exact cut varies by exam form (IRT), so NCARB
// publishes a RANGE, not a single number, and does not publish a raw-to-scaled
// conversion. This screen therefore only reports where a practice score falls
// relative to that range — it cannot and does not predict an official result.
// Source: ncarb.org/blog/what-score-do-you-need-to-pass-the-are
typedef PassingRange = ({int min, int max});

const _passingRanges = <String, PassingRange>{
  'PcM': (min: 59, max: 71),
  'PjM': (min: 59, max: 71),
  'PA': (min: 65, max: 71),
  'PPD': (min: 65, max: 71),
  'PDD': (min: 58, max: 66),
  'CE': (min: 58, max: 66),
};

const _divisionNames = {
  'PcM': 'Practice Management',
  'PjM': 'Project Management',
  'CE': 'Construction & Evaluation',
  'PA': 'Programming & Analysis',
  'PPD': 'Project Planning & Design',
  'PDD': 'Project Development & Documentation',
};

class NcarbCalculatorScreen extends StatefulWidget {
  const NcarbCalculatorScreen({super.key});

  @override
  State<NcarbCalculatorScreen> createState() => _NcarbCalculatorScreenState();
}

class _NcarbCalculatorScreenState extends State<NcarbCalculatorScreen> {
  String _division = 'PcM';
  final _scoreController = TextEditingController();
  int? _rawScore;

  @override
  void dispose() {
    _scoreController.dispose();
    super.dispose();
  }

  PassingRange get _range => _passingRanges[_division]!;

  /// Where a raw score sits relative to NCARB's published passing range.
  /// Deliberately not a pass/fail prediction: NCARB does not disclose which
  /// cut applies to a given exam form.
  _Band _bandFor(int raw) {
    if (raw < _range.min) return _Band.below;
    if (raw > _range.max) return _Band.above;
    return _Band.within;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        title: const Text('Practice Score Check'),
        backgroundColor: AppTheme.navy.withValues(alpha: 0.92),
        foregroundColor: AppTheme.textPrimary,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
          // Division selector
          const Text(
            'Division',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _passingRanges.keys.map((div) {
              final selected = _division == div;
              return GestureDetector(
                onTap: () => setState(() {
                  _division = div;
                  _rawScore = null;
                  _scoreController.clear();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.yellow.withValues(alpha: 0.15)
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppTheme.yellow : AppTheme.separator,
                      width: selected ? 1.5 : 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        div,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppTheme.yellow : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _divisionNames[div]!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),
          const Text(
            'Your Raw Score (%)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _scoreController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18),
            decoration: InputDecoration(
              hintText: '0 – 100',
              hintStyle: const TextStyle(color: AppTheme.textSecondary),
              suffixText: '%',
              suffixStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 18),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.separator, width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.yellow, width: 1.5),
              ),
            ),
            onChanged: (v) {
              final parsed = int.tryParse(v);
              setState(() => _rawScore = (parsed != null && parsed <= 100) ? parsed : null);
            },
          ),

          const SizedBox(height: 28),

          // Result card
          if (_rawScore != null) _ResultCard(
            raw: _rawScore!,
            range: _range,
            band: _bandFor(_rawScore!),
          ),

          const SizedBox(height: 24),

          // Passing-range reference table
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.separator, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'NCARB PASSING RANGES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('https://www.ncarb.org/blog/what-score-do-you-need-to-pass-the-are'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text(
                        'official source ↗',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._passingRanges.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.yellow.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            e.key,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.yellow,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _divisionNames[e.key]!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                      Text(
                        '${e.value.min}–${e.value.max}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'This is a practice check, not a score prediction. The ranges above are '
            'NCARB\'s published passing ranges — the share of scored items needed to pass. '
            'The exact cut depends on your exam form, and NCARB does not publish how a raw '
            'percentage converts to the 100–800 scaled score (550 = pass). No app can '
            'predict your official result; only your NCARB score report is authoritative.',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Band { below, within, above }

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.raw,
    required this.range,
    required this.band,
  });

  final int raw;
  final PassingRange range;
  final _Band band;

  @override
  Widget build(BuildContext context) {
    final (label, sublabel, color, icon) = switch (band) {
      _Band.below => (
          'Below the passing range',
          'Even the most forgiving form of this division needs ${range.min}% of scored '
              'items correct. Keep practising.',
          AppTheme.error,
          Icons.trending_down_rounded,
        ),
      _Band.within => (
          'Inside the passing range',
          'This division passes somewhere between ${range.min}% and ${range.max}%, depending '
              'on your exam form. NCARB does not disclose which cut applies, so this could '
              'go either way.',
          AppTheme.warning,
          Icons.remove_rounded,
        ),
      _Band.above => (
          'Above the passing range',
          'You are above the highest published cut (${range.max}%) for this division. Still '
              'not a guarantee — only NCARB scores the real exam.',
          AppTheme.success,
          Icons.trending_up_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sublabel,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ScoreStat('Your Score', '$raw%', AppTheme.textPrimary),
              Container(width: 1, height: 32, color: AppTheme.separator),
              _ScoreStat('Passing Range', '${range.min}–${range.max}%', AppTheme.textSecondary),
              Container(width: 1, height: 32, color: AppTheme.separator),
              _ScoreStat(
                'To Range Min',
                '${raw - range.min > 0 ? '+' : ''}${raw - range.min}%',
                color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreStat extends StatelessWidget {
  const _ScoreStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}
