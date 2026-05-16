import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';

/// Shared action row layout used by media detail screens.
///
/// Renders icon actions on the left and a primary play control on the right.
class MediaActionRow extends StatelessWidget {
  const MediaActionRow({
    required this.actions,
    required this.playControl,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    super.key,
  });

  final List<Widget> actions;
  final Widget playControl;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [...actions, const Spacer(), playControl]),
    );
  }
}
