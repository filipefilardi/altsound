import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        SizedBox(
          height: 220,
          child: items.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _ShelfSkeleton(),
                SizedBox(width: 12),
                _ShelfSkeleton(),
                SizedBox(width: 12),
                _ShelfSkeleton(),
              ]),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Couldn\'t load: $e',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Nothing here yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
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
    return Container(
      width: 152,
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
