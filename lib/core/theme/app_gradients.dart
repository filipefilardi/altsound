import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppGradients {
  AppGradients._();

  /// Solid primary fill exposed as a gradient for controls that already use a
  /// gradient decoration.
  static const accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primary],
  );

  /// Slim version for thin progress bars.
  static const accentHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.primary],
  );

  /// Solid dark charcoal backdrop for the login screen.
  static const loginBackdrop = RadialGradient(
    center: Alignment(0, -0.6),
    radius: 1.1,
    colors: [AppColors.background, AppColors.background],
    stops: [0.0, 0.85],
  );
}
