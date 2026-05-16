import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';

class PinnedActionBarDelegate extends SliverPersistentHeaderDelegate {
  PinnedActionBarDelegate({
    required this.child,
    this.height = 72,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    this.backgroundColor = AppColors.background,
  });

  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, padding: padding, child: child);
  }

  @override
  bool shouldRebuild(covariant PinnedActionBarDelegate oldDelegate) {
    return child != oldDelegate.child ||
        height != oldDelegate.height ||
        padding != oldDelegate.padding ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
