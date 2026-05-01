import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF0B0E12);
  static const surface = Color(0xFF151922);
  static const surfaceElevated = Color(0xFF1B212B);
  static const surfaceHighlight = Color(0xFF242B36);

  static const primary = Color(0xFF7B68EE);
  static const primaryDark = Color(0xFF5A4EC8);
  static const accent = Color(0xFFA78BFA);

  /// Foreground color used on top of primary controls (e.g. play pill icon).
  static const onAccent = Color(0xFF0E0820);

  static const textPrimary = Color(0xFFF7F8F5);
  static const textSecondary = Color(0xFFA6B4B8);
  static const textTertiary = Color(0xFF617279);

  static const divider = Color(0xFF2D3540);
  static const error = Color(0xFFE5635A);

  /// "Liked songs" heart color. Kept separate so the two can diverge without
  /// coupling failure UI to favorites UI.
  static const like = Color(0xFFE5635A);
}
