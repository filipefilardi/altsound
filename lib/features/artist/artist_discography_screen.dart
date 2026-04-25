import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import 'artist_screen.dart';

class ArtistDiscographyScreen extends ConsumerWidget {
  const ArtistDiscographyScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistProvider(artistId));
    return Scaffold(
      appBar: AppBar(title: const Text('Discography')),
      body: async.when(
        loading: () => const _DiscographyLoading(),
        error: (e, _) => ErrorStateView(
          title: "Couldn't load this discography",
          message: e.toString(),
          onRetry: () => ref.invalidate(artistProvider(artistId)),
        ),
        data: (artist) {
          if (artist.albums.isEmpty) {
            return const Center(
              child: Text(
                'No albums found in your Jellyfin library.',
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
              childAspectRatio: 0.7,
            ),
            itemCount: artist.albums.length,
            itemBuilder: (_, i) {
              final album = artist.albums[i];
              final imageUrl =
                  repo.imageUrl(album.id, imageTag: album.imageTag, size: 400);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push('/album/${album.id}'),
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
                              Container(color: AppColors.surfaceElevated),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceElevated,
                            child: const Icon(
                              Icons.album,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      album.subtitle ?? 'Album',
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

class _DiscographyLoading extends StatelessWidget {
  const _DiscographyLoading();

  @override
  Widget build(BuildContext context) {
    return Skeleton.group(
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: 8,
        itemBuilder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Skeleton.box(width: double.infinity, height: double.infinity),
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
