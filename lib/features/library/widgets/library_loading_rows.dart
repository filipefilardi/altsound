import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/skeleton.dart';

class LibraryLoadingRows extends StatelessWidget {
  const LibraryLoadingRows({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: Column(
        children: [
          for (int i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Skeleton.box(width: 52, height: 52, radius: 12),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton.line(width: 160, height: 14),
                        const SizedBox(height: AppSpacing.sm),
                        Skeleton.line(width: 100, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
