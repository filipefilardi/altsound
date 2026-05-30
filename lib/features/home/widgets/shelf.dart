import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/layout/adaptive_breakpoints.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/horizontal_shelf_with_arrows.dart';
import 'package:altsound/core/widgets/skeleton.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/home/widgets/media_card.dart';

class Shelf extends ConsumerStatefulWidget {
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
  ConsumerState<Shelf> createState() => _ShelfState();
}

class _ShelfState extends ConsumerState<Shelf> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopLayout(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (widget.onSeeAll != null)
                TextButton(
                  onPressed: widget.onSeeAll,
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        HorizontalShelfWithArrows(
          controller: _controller,
          enabled: desktop,
          child: SizedBox(
            height: 220,
            child: widget.items.when(
              loading: () => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Skeleton.group(
                  child: Row(
                    children: const [
                      _ShelfSkeleton(),
                      SizedBox(width: AppSpacing.sm),
                      _ShelfSkeleton(),
                      SizedBox(width: AppSpacing.sm),
                      _ShelfSkeleton(),
                    ],
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  "Couldn't load",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      'Nothing here yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, i) => MediaCard(item: list[i]),
                );
              },
            ),
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
        const SizedBox(height: AppSpacing.sm),
        Skeleton.line(width: 120),
        const SizedBox(height: AppSpacing.sm),
        Skeleton.line(width: 80, height: 10),
      ],
    );
  }
}
