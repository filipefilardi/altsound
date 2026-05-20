import 'package:flutter/material.dart';
import 'package:picons/picons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/player/playback_handler.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/player_error_banner.dart';
import 'package:altsound/features/player/widgets/player_hero_art.dart';
import 'package:altsound/features/player/widgets/player_main_controls.dart';
import 'package:altsound/features/player/widgets/player_scrubber.dart';
import 'package:altsound/features/player/widgets/player_secondary_controls.dart';
import 'package:altsound/features/player/widgets/player_surface.dart';
import 'package:altsound/features/player/widgets/player_top_bar.dart';
import 'package:altsound/features/player/widgets/queue_bottom_sheet.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  PlayerError? _error;
  ProviderSubscription<AsyncValue<PlayerError>>? _errorSub;

  void _openLyrics() {
    HapticFeedback.selectionClick();
    context.push('/lyrics');
  }

  @override
  void initState() {
    super.initState();
    _errorSub = ref.listenManual(playerErrorProvider, (_, next) {
      next.whenData((err) {
        if (!mounted) return;
        setState(() => _error = err);
      });
    });
  }

  @override
  void dispose() {
    _errorSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(effectiveMediaItemProvider);
    final playing = ref.watch(effectivePlayingProvider);
    final artistId = mediaItem?.extras?['artistId'] as String?;
    final albumId = mediaItem?.extras?['albumId'] as String?;

    if (mediaItem == null) {
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
                    PlayerTopBar(
                      album: mediaItem.album ?? '',
                      albumId: albumId,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final maxArt = constraints.maxWidth.clamp(0, 360.0);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Center(
                                  child: GestureDetector(
                                    onDoubleTap: _openLyrics,
                                    child: PlayerHeroArt(
                                      size: maxArt.toDouble(),
                                      mediaItem: mediaItem,
                                      hero: true,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                mediaItem.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              InkWell(
                                onTap: artistId == null || artistId.isEmpty
                                    ? null
                                    : () => context.push('/artist/$artistId'),
                                child: Text(
                                  mediaItem.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontSize: 14,
                                        color:
                                            artistId == null || artistId.isEmpty
                                            ? AppColors.textSecondary
                                            : AppColors.primary,
                                      ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (_error != null) ...[
                      PlayerErrorBanner(
                        error: _error!,
                        onSkip: () {
                          ref.read(playerControllerProvider).next();
                          setState(() => _error = null);
                        },
                        onDismiss: () => setState(() => _error = null),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    PlayerSecondaryControls(mediaItem: mediaItem),
                    const SizedBox(height: AppSpacing.md),
                    const PlayerScrubber(),
                    const SizedBox(height: AppSpacing.md),
                    PlayerMainControls(
                      playing: playing,
                      onLyrics: _openLyrics,
                      onQueue: () => showQueueBottomSheet(context, ref),
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
