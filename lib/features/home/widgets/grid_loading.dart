import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/skeleton.dart';

/// Loading skeleton for media grids (e.g. recently-added albums).
class GridLoading extends StatelessWidget {
  const GridLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: 12,
        itemBuilder: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Skeleton.box(
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Skeleton.line(height: 12),
            const SizedBox(height: AppSpacing.sm),
            Skeleton.line(width: 80, height: 10),
          ],
        ),
      ),
    );
  }
}
