import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/artwork_placeholder.dart';
import 'package:altsound/core/widgets/error_state.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/features/home/home_controller.dart';
import 'package:altsound/features/home/widgets/grid_loading.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';

class RecentlyAddedScreen extends ConsumerWidget {
  const RecentlyAddedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentlyAddedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recently Added')),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: async.when(
        loading: () => const GridLoading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load recently added",
          message: e.toString(),
          onRetry: () => ref.invalidate(recentlyAddedProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'Nothing here yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          final repo = ref.watch(jellyfinRepositoryProvider);
          return GridView.builder(
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
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              final imageUrl = (item.imageTag == null || item.imageTag!.isEmpty)
                  ? null
                  : repo.imageUrl(item.id, imageTag: item.imageTag, size: 400);
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => context.push('/album/${item.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: imageUrl == null
                            ? const ArtworkPlaceholder()
                            : CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const ColoredBox(
                                  color: AppColors.surfaceElevated,
                                ),
                                errorWidget: (_, __, ___) =>
                                    const ArtworkPlaceholder(),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
