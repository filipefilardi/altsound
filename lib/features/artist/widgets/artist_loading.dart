import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/skeleton.dart';

class ArtistLoading extends StatelessWidget {
  const ArtistLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            leading: const BackButton(),
            flexibleSpace: FlexibleSpaceBar(
              background: Skeleton.box(
                width: double.infinity,
                height: double.infinity,
                radius: 0,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Skeleton.line(width: 120, height: 16),
                const SizedBox(height: AppSpacing.md),
                for (int i = 0; i < 5; i++) ...[
                  Skeleton.line(height: 14),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
