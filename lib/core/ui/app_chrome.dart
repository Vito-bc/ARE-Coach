import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_spacing.dart';
import 'app_tappable.dart';

/// The canonical content card: surface fill, hairline border, rounded corners.
///
/// Replaces the older [AppGlassCard], the per-screen `_Card`s, and raw
/// decorated `Container`s. Pass [onTap] to make the whole card tappable with
/// built-in press feedback. Pass [accentBorder] to highlight it.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.accentBorder,
    this.borderWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// When set, draws the card border in this colour (e.g. an accent highlight).
  final Color? accentBorder;
  final double? borderWidth;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: accentBorder ?? AppTheme.separator,
          width: borderWidth ?? (accentBorder != null ? 1 : 0.5),
        ),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return AppTappable(onTap: onTap, child: card);
  }
}

/// Dark surface card — ArchiEd urban night palette.
class AppGlassCard extends StatelessWidget {
  const AppGlassCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: child,
    );
  }
}

/// Grouped section — labeled block of cards.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: tt.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        AppGlassCard(child: child),
      ],
    );
  }
}

/// Stat pill — small chip showing a number and label.
class AppStatPill extends StatelessWidget {
  const AppStatPill({
    super.key,
    required this.value,
    required this.label,
    this.color,
  });

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Legacy backdrop — kept for screens still referencing it.
/// Renders as the dark navy background.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/bg_hero.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const ColoredBox(color: AppTheme.navy),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xB30D1117),
                Color(0xD90D1117),
                Color(0xF20D1117),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
