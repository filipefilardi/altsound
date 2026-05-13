import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';
import 'package:altsound/features/player/now_playing_screen.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/lyrics_view.dart';

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
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const PlayerDragHandle(),
                    const SizedBox(height: 4),
                    _LyricsTopBar(
                      label: headerLabel,
                      album: albumName,
                      albumId: albumId,
                      castConnected: castConnected,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: LyricsView(trackId: trackId),
                      ),
                    ),
                    const PlayerScrubber(),
                    const SizedBox(height: 16),
                    PlayerPlayPauseButton(
                      playing: playing,
                      onTap: controller.togglePlay,
                    ),
                    const SizedBox(height: 24),
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
class _LyricsTopBar extends StatelessWidget {
  const _LyricsTopBar({
    required this.label,
    required this.album,
    required this.albumId,
    required this.castConnected,
  });

  final String label;
  final String album;
  final String? albumId;
  final bool castConnected;

  @override
  Widget build(BuildContext context) {
    // Single icon on the left (~48 px). Reserve same on the right so the
    // centered text stays centered.
    const sideReserve = 48.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: sideReserve),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontSize: 10,
                              letterSpacing: 1.6,
                              color: castConnected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      InkWell(
                        onTap: albumId == null || albumId!.isEmpty || album.isEmpty
                            ? null
                            : () {
                                context.pop();
                                context.push('/album/$albumId');
                              },
                        child: Text(
                          album,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: albumId == null ||
                                    albumId!.isEmpty ||
                                    album.isEmpty
                                ? AppColors.textPrimary
                                : AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                onPressed: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
