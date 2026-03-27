import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/ui/app_chrome.dart';
import '../services/iap_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.iapService});

  final IAPService iapService;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  List<ProductDetails> _products = [];
  bool _loading = true;
  String? _errorMessage;
  String _selectedId = IAPService.kYearlyId;
  bool _purchasing = false;

  static const List<_Feature> _features = [
    _Feature(Icons.psychology_outlined, 'AI Coach — unlimited sessions'),
    _Feature(Icons.grid_view_rounded, 'All 6 ARE divisions unlocked'),
    _Feature(Icons.bar_chart_rounded, 'Progress analytics & readiness score'),
    _Feature(Icons.mic_outlined, 'Voice-assisted practice mode'),
  ];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    widget.iapService.purchaseUpdates.listen(_onPurchaseUpdate);
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final products = await widget.iapService.loadProducts();
      if (mounted) {
        setState(() {
          _products = products
            ..sort((a, b) => a.id == IAPService.kMonthlyId ? -1 : 1);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not reach the App Store. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  void _onPurchaseUpdate(PurchaseDetails details) {
    if (!mounted) return;
    if (details.status == PurchaseStatus.purchased ||
        details.status == PurchaseStatus.restored) {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Premium!')),
      );
      Navigator.of(context).pop(true);
    } else if (details.status == PurchaseStatus.error) {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            details.error?.message ?? 'Purchase failed. Please try again.',
          ),
        ),
      );
    } else if (details.status == PurchaseStatus.pending) {
      setState(() => _purchasing = true);
    }
  }

  ProductDetails? get _selectedProduct {
    try {
      return _products.firstWhere((p) => p.id == _selectedId);
    } catch (_) {
      return _products.isNotEmpty ? _products.first : null;
    }
  }

  Future<void> _subscribe() async {
    final product = _selectedProduct;
    if (product == null || _purchasing) return;
    setState(() => _purchasing = true);
    try {
      await widget.iapService.purchaseSubscription(product);
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not initiate purchase.')),
        );
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _purchasing = true);
    try {
      await widget.iapService.restorePurchases();
    } catch (e) {
      if (mounted) {
        setState(() => _purchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                    children: [
                      _buildHeader(tt, isDark),
                      const SizedBox(height: 28),
                      _buildFeatureCard(isDark, tt),
                      const SizedBox(height: 20),
                      _buildProductSection(isDark, tt, cs),
                    ],
                  ),
                ),
                _buildFooter(isDark, tt),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(TextTheme tt, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0EA5E9), const Color(0xFF06B6D4)]
                  : [const Color(0xFF111827), const Color(0xFF1D4ED8)],
            ),
          ),
          child: const Icon(Icons.architecture, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),
        Text('Architectula Premium', style: tt.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          'Everything you need to pass the ARE.',
          style: tt.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFeatureCard(bool isDark, TextTheme tt) {
    return AppGlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What\'s included', style: tt.titleMedium),
          const SizedBox(height: 14),
          ..._features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    f.icon,
                    size: 20,
                    color: isDark
                        ? const Color(0xFF67E8F9)
                        : const Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f.label, style: tt.bodyMedium)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSection(bool isDark, TextTheme tt, ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return AppGlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(_errorMessage!, style: tt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return AppGlassCard(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No products available in your region.',
          style: tt.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: _products.map((product) {
        final isYearly = product.id == IAPService.kYearlyId;
        final isSelected = _selectedId == product.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ProductCard(
            product: product,
            isYearly: isYearly,
            isSelected: isSelected,
            isDark: isDark,
            tt: tt,
            cs: cs,
            onTap: () => setState(() => _selectedId = product.id),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFooter(bool isDark, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: (_purchasing || _selectedProduct == null) ? null : _subscribe,
            child: _purchasing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Subscribe Now'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _purchasing ? null : _restore,
            child: const Text('Restore Purchases'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Continue with Free',
              style: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.45)
                    : const Color(0xFF6B7280),
                fontSize: 13,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in your Apple ID settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : const Color(0xFF9CA3AF),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.isYearly,
    required this.isSelected,
    required this.isDark,
    required this.tt,
    required this.cs,
    required this.onTap,
  });

  final ProductDetails product;
  final bool isYearly;
  final bool isSelected;
  final bool isDark;
  final TextTheme tt;
  final ColorScheme cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? (isDark ? const Color(0xFF0EA5E9) : const Color(0xFF111827))
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFE5E7EB));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? (isDark
                  ? const Color(0xFF0EA5E9).withValues(alpha: 0.12)
                  : const Color(0xFF111827).withValues(alpha: 0.06))
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.94)),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? (isDark ? const Color(0xFF0EA5E9) : const Color(0xFF111827))
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.35)
                          : const Color(0xFF9CA3AF)),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isYearly ? 'Yearly' : 'Monthly',
                        style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (isYearly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                            ),
                          ),
                          child: const Text(
                            'Best Value',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isYearly ? 'Billed annually' : 'Billed monthly',
                    style: tt.bodyMedium?.copyWith(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : const Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              product.price,
              style: tt.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? (isDark ? const Color(0xFF67E8F9) : const Color(0xFF111827))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;
}
