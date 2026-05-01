import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({
    super.key,
    this.icon = Icons.album,
    this.iconSize = 40,
    this.iconColor = AppColors.textTertiary,
    this.backgroundColor = AppColors.surfaceElevated,
  });

  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: backgroundColor,
      child: Center(
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}
