import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/skeleton.dart';
import '../../../data/jellyfin/models/media_item.dart';
import 'media_card.dart';

class Shelf extends ConsumerWidget {
  const Shelf({
    required this.title,
    required this.items,
    super.key,
  });

  final String title;
  final AsyncValue<List<BrowseItem>> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        SizedBox(
          height: 220,
          child: items.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Skeleton.group(
                child: Row(
                  children: const [
                    _ShelfSkeleton(),
                    SizedBox(width: 12),
                    _ShelfSkeleton(),
                    SizedBox(width: 12),
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
