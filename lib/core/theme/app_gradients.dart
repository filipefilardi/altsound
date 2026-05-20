import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_colors.dart';

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

  /// Soft primary-tinted radial used on the login backdrop.
  static const loginBackdrop = RadialGradient(
    center: Alignment(0, -0.6),
    radius: 1.1,
    colors: [Color(0x338676F2), AppColors.background],
    stops: [0.0, 0.85],
  );
}
