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
import 'package:altsound/features/artist/artist_screen.dart';
import 'package:altsound/features/artist/widgets/discography_loading.dart';
import 'package:altsound/features/player/widgets/mini_player_slot.dart';

class ArtistDiscographyScreen extends ConsumerWidget {
  const ArtistDiscographyScreen({required this.artistId, super.key});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistProvider(artistId));
    return Scaffold(
      appBar: AppBar(title: const Text('Discography')),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: async.when(
        loading: () => const DiscographyLoading(),
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
              childAspectRatio: 0.7,
            ),
            itemCount: artist.albums.length,
            itemBuilder: (_, i) {
              final album = artist.albums[i];
              final imageUrl =
                  (album.imageTag == null || album.imageTag!.isEmpty)
                  ? null
                  : repo.imageUrl(
                      album.id,
                      imageTag: album.imageTag,
                      size: 400,
                    );
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => context.push('/album/${album.id}'),
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
                                placeholder: (_, _) =>
                                    Container(color: AppColors.surfaceElevated),
                                errorWidget: (_, _, _) =>
                                    const ArtworkPlaceholder(),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
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
