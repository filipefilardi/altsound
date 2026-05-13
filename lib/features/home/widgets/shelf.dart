import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/widgets/skeleton.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/home/widgets/media_card.dart';

class Shelf extends ConsumerWidget {
  const Shelf({
    required this.title,
    required this.items,
    this.onSeeAll,
    super.key,
  });

  final String title;
  final AsyncValue<List<BrowseItem>> items;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 4, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: items.when(
            loading: () => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Skeleton.group(
                child: Row(
                  children: const [
                    _ShelfSkeleton(),
                    SizedBox(width: 6),
                    _ShelfSkeleton(),
                    SizedBox(width: 6),
                    _ShelfSkeleton(),
                  ],
                ),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "Couldn't load",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Nothing here yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => MediaCard(item: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ShelfSkeleton extends StatelessWidget {
  const _ShelfSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Skeleton.box(width: 156, height: 156, radius: 12),
        const SizedBox(height: 10),
        Skeleton.line(width: 120),
        const SizedBox(height: 6),
        Skeleton.line(width: 80, height: 10),
      ],
    );
  }
}
