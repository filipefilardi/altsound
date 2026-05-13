import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight =
              constraints.maxHeight.isFinite && constraints.maxHeight < 180;
          final compact =
              constraints.maxHeight.isFinite && constraints.maxHeight < 260;
          final padding = tight
              ? 12.0
              : compact
              ? 20.0
              : 32.0;
          final showIcon = !tight;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIcon) ...[
                  Container(
                    width: compact ? 52 : 64,
                    height: compact ? 52 : 64,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: AppColors.textSecondary,
                      size: compact ? 24 : 28,
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 20),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: tight ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (message != null && !tight) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (action != null && !tight) ...[
                  SizedBox(height: compact ? 14 : 20),
                  action!,
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
