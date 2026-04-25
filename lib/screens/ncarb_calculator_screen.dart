import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

// Approximate raw-score cut points per division.
// NCARB uses IRT scaling (passing scaled score = 265 on a 200-400 scale).
// These percentages are community-reported estimates — not official NCARB data.
const _cutScores = {
  'PcM': 58,
  'PjM': 60,
  'CE': 62,
  'PA': 60,
  'PPD': 63,
  'PDD': 63,
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

  int get _cutScore => _cutScores[_division]!;

  _Verdict _verdict(int raw) {
    final diff = raw - _cutScore;
    if (diff >= 5) return _Verdict.pass;
    if (diff >= -4) return _Verdict.borderline;
    return _Verdict.fail;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        title: const Text('NCARB Score Calculator'),
        backgroundColor: AppTheme.navy,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: ListView(
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
            children: _cutScores.keys.map((div) {
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
            cut: _cutScore,
            division: _division,
            verdict: _verdict(_rawScore!),
          ),

          const SizedBox(height: 24),

          // Cut score reference table
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
                const Text(
                  'ESTIMATED CUT SCORES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ..._cutScores.entries.map((e) => Padding(
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
                        '~${e.value}%',
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
            'Disclaimer: Cut scores are community-reported estimates based on NCARB\'s scaled passing score of 265. Actual results depend on exam form difficulty and IRT scaling. Always refer to official NCARB score reports.',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Verdict { pass, borderline, fail }

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.raw,
    required this.cut,
    required this.division,
    required this.verdict,
  });

  final int raw;
  final int cut;
  final String division;
  final _Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final (label, sublabel, color, icon) = switch (verdict) {
      _Verdict.pass => (
          'Likely Pass',
          'Your score is comfortably above the estimated cut score.',
          AppTheme.success,
          Icons.check_circle_rounded,
        ),
      _Verdict.borderline => (
          'Borderline',
          'Your score is within the margin of error. Result could go either way.',
          AppTheme.warning,
          Icons.info_rounded,
        ),
      _Verdict.fail => (
          'Likely Fail',
          'Your score is below the estimated cut score. More practice recommended.',
          AppTheme.error,
          Icons.cancel_rounded,
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
              _ScoreStat('Est. Cut', '~$cut%', AppTheme.textSecondary),
              Container(width: 1, height: 32, color: AppTheme.separator),
              _ScoreStat('Margin', '${raw - cut > 0 ? '+' : ''}${raw - cut}%', color),
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
