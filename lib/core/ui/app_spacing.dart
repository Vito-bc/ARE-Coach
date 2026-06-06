/// Shared spacing and radius scale.
///
/// Use these instead of ad-hoc magic numbers so vertical rhythm and corner
/// rounding stay consistent across screens. Based on a 4-pt grid.
library;

abstract final class AppSpacing {
  /// 4
  static const double xs = 4;

  /// 8
  static const double sm = 8;

  /// 12
  static const double md = 12;

  /// 16 — default card padding / content inset
  static const double lg = 16;

  /// 20 — default screen horizontal padding
  static const double xl = 20;

  /// 24 — gap between major sections
  static const double xxl = 24;

  /// 32 — large section break
  static const double xxxl = 32;
}

abstract final class AppRadius {
  /// 8 — small chips / inner elements
  static const double sm = 8;

  /// 12 — buttons, inputs, inner cards
  static const double md = 12;

  /// 16 — standard cards
  static const double lg = 16;

  /// 20 — pills / fully-rounded chips
  static const double pill = 20;
}
