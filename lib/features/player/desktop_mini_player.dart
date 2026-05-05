import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import 'current_track_playlist_presence.dart';
import 'instant_mix.dart';
import 'player_providers.dart';
import 'widgets/add_track_to_playlist_sheet.dart';
import 'widgets/player_hero_art.dart';
import 'widgets/queue_bottom_sheet.dart';

class DesktopMiniPlayer extends ConsumerWidget {
  const DesktopMiniPlayer({this.edgeToEdge = true, super.key});

  final bool edgeToEdge;
  static const _controlButtonConstraints = BoxConstraints.tightFor(
    width: 38,
    height: 38,
  );
  static const _auxButtonConstraints = BoxConstraints.tightFor(
    width: 32,
    height: 32,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(effectiveMediaItemProvider);
    if (mediaItem == null) return const SizedBox.shrink();

    final controller = ref.read(playerControllerProvider);
    final playing = ref.watch(effectivePlayingProvider);
    final position = ref.watch(effectivePositionProvider);
    final duration = ref.watch(effectiveDurationProvider);
    final shuffled = ref.watch(playerShuffleEnabledProvider).value ?? false;
    final loopMode = ref.watch(playerLoopModeProvider).value ?? LoopMode.off;
    final presenceAsync = ref.watch(currentTrackPlaylistPresenceProvider);
    final saved = switch (presenceAsync) {
      AsyncData(:final value) => value.isSaved,
      _ => false,
    };
    final artistId = mediaItem.extras?['artistId'] as String?;
    final albumId = mediaItem.extras?['albumId'] as String?;
    final horizontal = edgeToEdge ? 16.0 : 10.0;
    final clampedPosition = position > duration ? duration : position;
    final sliderMax = duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final sliderValue = clampedPosition.inMilliseconds.toDouble().clamp(
      0.0,
      sliderMax,
    );
    final volume = ref.watch(playerVolumeProvider).value ?? 1.0;
    final muted = controller.isEffectivelyMuted || volume <= 0.001;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: const Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surfaceElevated.withValues(alpha: 0.94),
            AppColors.surface,
          ],
        ),
      ),
      child: SizedBox(
        height: 82,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 320,
                child: Row(
                  children: [
                    PlayerHeroArt(size: 52, mediaItem: mediaItem, hero: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          InkWell(
                            onTap: albumId == null || albumId.isEmpty
                                ? null
                                : () => context.push('/album/$albumId'),
                            child: Text(
                              mediaItem.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: artistId == null || artistId.isEmpty
                                ? null
                                : () => context.push('/artist/$artistId'),
                            child: Text(
                              mediaItem.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: artistId == null || artistId.isEmpty
                                    ? AppColors.textSecondary
                                    : AppColors.primary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.shuffle_rounded,
                            size: 20,
                            color: shuffled
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          onPressed: controller.toggleShuffle,
                          tooltip: 'Shuffle',
                          padding: EdgeInsets.zero,
                          constraints: _auxButtonConstraints,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            size: 24,
                          ),
                          onPressed: controller.previous,
                          tooltip: 'Previous',
                          padding: EdgeInsets.zero,
                          constraints: _controlButtonConstraints,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: Icon(
                            playing
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            size: 40,
                          ),
                          onPressed: controller.togglePlay,
                          tooltip: playing ? 'Pause' : 'Play',
                          padding: EdgeInsets.zero,
                          constraints: _controlButtonConstraints,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, size: 24),
                          onPressed: controller.next,
                          tooltip: 'Next',
                          padding: EdgeInsets.zero,
                          constraints: _controlButtonConstraints,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            loopMode == LoopMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            size: 20,
                            color: loopMode == LoopMode.off
                                ? AppColors.textSecondary
                                : AppColors.primary,
                          ),
                          onPressed: controller.cycleRepeatMode,
                          tooltip: 'Repeat',
                          padding: EdgeInsets.zero,
                          constraints: _auxButtonConstraints,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                formatDuration(clampedPosition),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  activeTrackColor: AppColors.textPrimary,
                                  inactiveTrackColor: AppColors.divider
                                      .withValues(alpha: 0.35),
                                  thumbColor: AppColors.textPrimary,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 10,
                                  ),
                                ),
                                child: Slider(
                                  value: sliderValue,
                                  min: 0,
                                  max: sliderMax,
                                  onChanged: (value) => controller.seek(
                                    Duration(milliseconds: value.toInt()),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 40,
                              child: Text(
                                formatDuration(duration),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 20,
                              ),
                              onPressed: () => openInstantMixPage(
                                context,
                                ref,
                                itemId: mediaItem.id,
                                kind: InstantMixSeedKind.track,
                                title: mediaItem.title,
                              ),
                              tooltip: 'Instant Mix',
                              padding: EdgeInsets.zero,
                              constraints: _auxButtonConstraints,
                              visualDensity: VisualDensity.compact,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: Icon(
                                muted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                size: 20,
                              ),
                              onPressed: controller.toggleMute,
                              tooltip: muted ? 'Unmute' : 'Mute',
                              padding: EdgeInsets.zero,
                              constraints: _auxButtonConstraints,
                              visualDensity: VisualDensity.compact,
                              color: muted
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: const Icon(
                                Icons.queue_music_rounded,
                                size: 20,
                              ),
                              onPressed: () =>
                                  showQueueBottomSheet(context, ref),
                              tooltip: 'Queue',
                              padding: EdgeInsets.zero,
                              constraints: _auxButtonConstraints,
                              visualDensity: VisualDensity.compact,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: Icon(
                                saved
                                    ? Icons.playlist_add_check_rounded
                                    : Icons.playlist_add_rounded,
                                size: 20,
                                color: saved
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              onPressed: () => unawaited(
                                _onDesktopPlaylistTap(
                                  context,
                                  ref,
                                  trackId: mediaItem.id,
                                ),
                              ),
                              tooltip: 'Add to playlist',
                              padding: EdgeInsets.zero,
                              constraints: _auxButtonConstraints,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _onDesktopPlaylistTap(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
}) async {
  await openManageTrackPlaylistsSheet(context, ref, trackId: trackId);
  ref.invalidate(currentTrackPlaylistPresenceProvider);
}
