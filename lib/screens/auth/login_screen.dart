import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.firebaseReady,
    this.onGuestContinue,
    AuthService? authService,
  }) : _authService = authService;

  static const routeName = '/login';

  final bool firebaseReady;
  final VoidCallback? onGuestContinue;
  final AuthService? _authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthService _authService = widget._authService ?? AuthService();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAppleSignIn() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signInWithApple();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        setState(() => _errorMessage = 'Apple sign-in failed. Please try again.');
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyAuthError(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleEmailSignIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyAuthError(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleContinueAsGuest() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await _authService.ensureSignedIn();
    } catch (_) {
      // proceed even if anonymous auth fails
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    widget.onGuestContinue?.call();
  }

  String _friendlyAuthError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Sign-in failed. Please try again.';
    }
  }

  bool get _showApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Hero background image (place your image at assets/images/bg_hero.jpg)
          _HeroBackground(),

          // Dark gradient overlay — strong at bottom for readability
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.35, 0.65, 1.0],
                colors: [
                  Color(0x99000000),
                  Color(0x44000000),
                  Color(0xBB0D1117),
                  Color(0xFF0D1117),
                ],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Top branding
                const Expanded(
                  flex: 3,
                  child: _Branding(),
                ),

                // Bottom form card
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    child: _FormCard(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      obscurePassword: _obscurePassword,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      errorMessage: _errorMessage,
                      loading: _loading,
                      showApple: _showApple,
                      onApple: _handleAppleSignIn,
                      onSignIn: _handleEmailSignIn,
                      onRegister: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              RegisterScreen(firebaseReady: widget.firebaseReady),
                        ),
                      ),
                      onGuest: _handleContinueAsGuest,
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

// ── Hero background ──────────────────────────────────────────────────────────

class _HeroBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Try to load the asset image; fall back to gradient if not present yet
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fallback gradient that matches the image palette
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFF1A2744), // deep blue (sky)
                Color(0xFF0D1117), // near-black (buildings)
                Color(0xFF1C1004), // very dark amber shadow
              ],
            ),
          ),
        ),
        // Actual image (shown when file exists)
        Image.asset(
          'assets/images/bg_hero.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Branding block ────────────────────────────────────────────────────────────

class _Branding extends StatelessWidget {
  const _Branding();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Yellow accent line
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.yellow,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ArchiEd',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
              color: AppTheme.white,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your path to ARE licensure.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSecondary,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ── Form card ─────────────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.errorMessage,
    required this.loading,
    required this.showApple,
    required this.onApple,
    required this.onSignIn,
    required this.onRegister,
    required this.onGuest,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final String? errorMessage;
  final bool loading;
  final bool showApple;
  final VoidCallback onApple;
  final VoidCallback onSignIn;
  final VoidCallback onRegister;
  final VoidCallback onGuest;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Apple sign in
          if (showApple) ...[
            SignInWithAppleButton(
              onPressed: loading ? () {} : onApple,
              style: SignInWithAppleButtonStyle.white,
              borderRadius: BorderRadius.circular(12),
              height: 52,
            ),
            const SizedBox(height: 20),
            _Divider(),
            const SizedBox(height: 20),
          ],

          // Email / password form
          Form(
            key: formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  style: const TextStyle(color: AppTheme.white),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter your email.';
                    }
                    if (!v.contains('@')) return 'Enter a valid email address.';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onSignIn(),
                  style: const TextStyle(color: AppTheme.white),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: onToggleObscure,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter your password.';
                    return null;
                  },
                ),
              ],
            ),
          ),

          // Error
          if (errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
              ),
              child: Text(
                errorMessage!,
                style: const TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 13.5,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Sign in button — yellow
          FilledButton(
            onPressed: loading ? null : onSignIn,
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.navy,
                    ),
                  )
                : const Text('Sign In'),
          ),

          const SizedBox(height: 10),

          // Create account — outlined
          OutlinedButton(
            onPressed: loading ? null : onRegister,
            child: const Text('Create Account'),
          ),

          const SizedBox(height: 16),

          // Guest
          Center(
            child: TextButton(
              onPressed: loading ? null : onGuest,
              child: const Text(
                'Continue as Guest',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: Divider(color: AppTheme.separator)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.separator)),
      ],
    );
  }
}
