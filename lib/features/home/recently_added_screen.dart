import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../player/widgets/mini_player_slot.dart';
import 'home_controller.dart';

class RecentlyAddedScreen extends ConsumerWidget {
  const RecentlyAddedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentlyAddedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recently Added')),
      bottomNavigationBar: const MiniPlayerSlot(withTopDivider: true),
      body: async.when(
        loading: () => const _GridLoading(),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              final imageUrl =
                  repo.imageUrl(item.id, imageTag: item.imageTag, size: 400);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push('/album/${item.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              const ColoredBox(color: AppColors.surfaceElevated),
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: AppColors.surfaceElevated,
                            child: Icon(
                              Icons.album,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
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

class _GridLoading extends StatelessWidget {
  const _GridLoading();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: 12,
        itemBuilder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Skeleton.box(
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            const SizedBox(height: 8),
            Skeleton.line(height: 12),
            const SizedBox(height: 6),
            Skeleton.line(width: 80, height: 10),
          ],
        ),
      ),
    );
  }
}
