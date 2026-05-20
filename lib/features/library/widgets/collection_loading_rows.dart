import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/skeleton.dart';

class CollectionLoadingRows extends StatelessWidget {
  const CollectionLoadingRows({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: ListView.builder(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.lg,
        ),
        itemCount: 10,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Skeleton.box(width: 52, height: 52, radius: 8),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(width: 180, height: 14),
                    const SizedBox(height: AppSpacing.sm),
                    Skeleton.line(width: 120, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
