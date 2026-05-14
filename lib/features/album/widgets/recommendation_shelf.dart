import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/skeleton.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/home/widgets/media_card.dart';

/// Horizontally-scrolling recommendation rail with a section title.
/// Renders skeletons while [items] is loading, hides entirely on error or
/// empty data.
class RecommendationShelf extends StatelessWidget {
  const RecommendationShelf({
    required this.title,
    required this.items,
    super.key,
  });

  final String title;
  final AsyncValue<List<BrowseItem>> items;

  @override
  Widget build(BuildContext context) {
    return items.when(
      loading: () => _RecommendationShelfFrame(
        title: title,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Skeleton.group(
            child: Row(
              children: const [
                _RecommendationSkeleton(),
                SizedBox(width: AppSpacing.sm),
                _RecommendationSkeleton(),
                SizedBox(width: AppSpacing.sm),
                _RecommendationSkeleton(),
              ],
            ),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _RecommendationShelfFrame(
          title: title,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) => MediaCard(item: items[i]),
          ),
        );
      },
    );
  }
}

class _RecommendationShelfFrame extends StatelessWidget {
  const _RecommendationShelfFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          SizedBox(height: 220, child: child),
        ],
      ),
    );
  }
}

class _RecommendationSkeleton extends StatelessWidget {
  const _RecommendationSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton.box(width: 156, height: 156, radius: 10),
          const SizedBox(height: AppSpacing.sm),
          Skeleton.line(width: 120),
          const SizedBox(height: AppSpacing.sm),
          Skeleton.line(width: 80, height: 10),
        ],
      ),
    );
  }
}
