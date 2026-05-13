import 'package:flutter/widgets.dart';

/// Canonical spacing scale. Values follow a 4dp grid.
///
/// Prefer these tokens over numeric literals in [EdgeInsets], [Padding],
/// and [SizedBox] gaps so spacing stays consistent across the app.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Bottom inset to clear the mini player + bottom nav.
  static const double miniPlayerInset = 96;

  // Common composite paddings -----------------------------------------------

  static const EdgeInsets screenHorizontal = EdgeInsets.symmetric(
    horizontal: md,
  );

  static const EdgeInsets miniPlayerBottom = EdgeInsets.only(
    bottom: miniPlayerInset,
  );

  // Common gaps -------------------------------------------------------------

  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
}
