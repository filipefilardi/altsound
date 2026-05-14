import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/skeleton.dart';

/// Skeleton placeholder shown while an album loads.
class AlbumLoading extends StatelessWidget {
  const AlbumLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Skeleton.group(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            0,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton.box(width: 220, height: 220),
                const SizedBox(height: AppSpacing.md),
                Skeleton.line(width: 220, height: 18),
                const SizedBox(height: AppSpacing.sm),
                Skeleton.line(width: 140, height: 12),
                const SizedBox(height: AppSpacing.lg),
                for (int i = 0; i < 8; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Row(
                      children: [
                        Skeleton.box(width: 28, height: 28, radius: 6),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Skeleton.line(height: 14)),
                        const SizedBox(width: AppSpacing.md),
                        Skeleton.line(width: 36, height: 12),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
