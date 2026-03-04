import 'package:flutter/material.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) {
      return Stack(
        children: [
          Container(color: const Color(0xFFF7F8FA)),
          Positioned.fill(
            child: CustomPaint(
              painter: _DayBlueprintPainter(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFEFF3F8).withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF020611),
                Color(0xFF06122A),
                Color(0xFF0C1A37),
              ],
            ),
          ),
        ),
        Positioned(
          left: -80,
          top: -40,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF1D4ED8).withValues(alpha: 0.32),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: -50,
          top: 80,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF06B6D4).withValues(alpha: 0.26),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        ...List.generate(18, (i) {
          final x = (i * 41) % 360;
          final y = (i * 73) % 680;
          return Positioned(
            left: x.toDouble(),
            top: y.toDouble(),
            child: Container(
              width: i % 3 == 0 ? 2.4 : 1.5,
              height: i % 3 == 0 ? 2.4 : 1.5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i % 3 == 0 ? 0.8 : 0.55),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ],
    );
  }
}

class AppGlassCard extends StatelessWidget {
  const AppGlassCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.96),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.14) : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          if (isDark)
            BoxShadow(
              color: const Color(0xFF67E8F9).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: child,
    );
  }
}

class _DayBlueprintPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.22)
      ..strokeWidth = 1;

    const spacing = 36.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * 0.35, size.height),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
