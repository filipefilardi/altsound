import 'package:flutter/widgets.dart';

/// Canonical corner-radius scale.
///
/// Prefer these tokens over numeric literals in [BorderRadius.circular] so
/// rounded corners stay consistent across cards, sheets, and inputs.
class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;

  /// Fully rounded ("pill") shape — use for chips, FAB-style buttons, etc.
  static const double pill = 999;

  // Common composite shapes -------------------------------------------------

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius xlAll = BorderRadius.circular(xl);
  static final BorderRadius xxlAll = BorderRadius.circular(xxl);
}
