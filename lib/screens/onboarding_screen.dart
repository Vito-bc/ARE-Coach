import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/theme/app_theme.dart';
import 'home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onDone});

  static const routeName = '/onboarding';

  /// Called when the user finishes onboarding. When provided, the screen
  /// delegates "what comes next" to the caller (the app shell decides whether
  /// to show Login or Home). When null it falls back to navigating Home.
  final VoidCallback? onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    if (widget.onDone != null) {
      widget.onDone!();
      return;
    }
    // Fallback (no host callback): persist the flag and go straight Home.
    final box = await Hive.openBox('settings');
    await box.put('onboarded', true);
    if (!mounted) return;
    unawaited(Navigator.of(context).pushReplacementNamed(HomeShell.routeName));
  }

  final _slides = const [
    (
      icon: Icons.location_city_rounded,
      title: 'ARE prep for NYC',
      text: 'Code-aware preparation with exam strategy and practical examples.',
    ),
    (
      icon: Icons.smart_toy_outlined,
      title: 'Personal AI coach',
      text:
          'Ask by text or voice and get formulas, code references, and mistake alerts.',
    ),
    (
      icon: Icons.rocket_launch_rounded,
      title: 'Start free, upgrade later',
      text:
          'Free tier for daily practice. Premium unlocks full coaching workflow.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.38).clamp(280.0, 480.0);

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fallback gradient (base layer, always visible)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFF1A2744),
                  Color(0xFF0D1117),
                  Color(0xFF1C1004),
                ],
              ),
            ),
          ),

          // 2. Hero image — full screen
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_hero.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

          // 3. Dark overlay for text readability
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3, 0.6, 1.0],
                colors: [
                  Color(0x66000000),
                  Color(0x33000000),
                  Color(0xCC0D1117),
                  Color(0xFF0D1117),
                ],
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // ARE Coach wordmark, top-left
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.yellow,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ARE Coach',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                            color: AppTheme.white,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // ── Card ─────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: SizedBox(
                    width: cardWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.separator,
                          width: 0.5,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 140,
                            child: PageView.builder(
                              controller: _controller,
                              itemCount: _slides.length,
                              onPageChanged: (v) => setState(() => _page = v),
                              itemBuilder: (_, index) {
                                final s = _slides[index];
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      s.icon,
                                      size: 32,
                                      color: AppTheme.yellow,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      s.title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.white,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      s.text,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _slides.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width: _page == i ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _page == i
                                      ? AppTheme.yellow
                                      : AppTheme.separator,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                if (_page < _slides.length - 1) {
                                  _controller.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                } else {
                                  _finishOnboarding();
                                }
                              },
                              child: Text(
                                _page == _slides.length - 1
                                    ? 'Start Free'
                                    : 'Continue',
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _finishOnboarding,
                              child: const Text('Sign In'),
                            ),
                          ),
                        ],
                      ),
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
