import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/lyrics_top_bar.dart';
import 'package:altsound/features/player/widgets/lyrics_view.dart';
import 'package:altsound/features/player/widgets/player_main_controls.dart';
import 'package:altsound/features/player/widgets/player_scrubber.dart';
import 'package:altsound/features/player/widgets/player_surface.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';

/// Full-screen lyrics view rendered on top of [NowPlayingScreen].
///
/// Layout mirrors the player chrome — minimize button, "PLAYING FROM ALBUM"
/// header, scrubber, and a single play/pause button — with the lyrics list in
/// the centre slot where the artwork normally lives.
class LyricsScreen extends ConsumerWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(effectiveMediaItemProvider);
    final playing = ref.watch(effectivePlayingProvider);
    final controller = ref.read(playerControllerProvider);
    final trackId = mediaItem?.extras?['jellyfinId'] as String?;
    final albumId = mediaItem?.extras?['albumId'] as String?;
    final remoteId = ref.watch(activeRemoteSessionIdProvider);
    final remoteSession = remoteId == null
        ? null
        : ref.watch(activeRemoteSessionProvider).value;
    final castConnected = remoteId != null;
    final headerLabel = castConnected
        ? 'PLAYING ON ${remoteSession?.deviceName.toUpperCase() ?? 'REMOTE'}'
        : 'PLAYING FROM ALBUM';
    final albumName = mediaItem?.album ?? '';

    if (mediaItem == null || trackId == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(PiconsRegular.caretDown),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Nothing playing')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const PlayerBackdrop(),
          SafeArea(
            child: PlayerDismissibleSurface(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    const PlayerDragHandle(),
                    const SizedBox(height: AppSpacing.xs),
                    LyricsTopBar(
                      label: headerLabel,
                      album: albumName,
                      albumId: albumId,
                      castConnected: castConnected,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: LyricsView(trackId: trackId),
                      ),
                    ),
                    const PlayerScrubber(),
                    const SizedBox(height: AppSpacing.md),
                    PlayerPlayPauseButton(
                      playing: playing,
                      onTap: controller.togglePlay,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim top bar — minimize button + centered "Playing from album" header.
/// No cast / queue / mic icons (this screen is itself the lyrics view).
