import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import 'now_playing_favorite.dart';
import 'player_providers.dart';
import 'widgets/player_hero_art.dart';
import 'widgets/queue_bottom_sheet.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    final state = ref.watch(playbackStateProvider).value;

    if (mediaItem == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Nothing playing')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _DraggableTopStrip(
              child: _TopBar(
                album: mediaItem.album ?? '',
                onQueue: () => showQueueBottomSheet(
                  context,
                  ref,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Builder(
                      builder: (c) {
                        final w = MediaQuery.sizeOf(c).width;
                        final side = (w - 40).clamp(0.0, 520.0);
                        return PlayerHeroArt(
                          size: side,
                          mediaItem: mediaItem,
                          hero: true,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                    Text(
                      mediaItem.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      mediaItem.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SecondaryControlsRow(mediaItem: mediaItem),
                    const SizedBox(height: 20),
                    const _VolumeRow(),
                    const SizedBox(height: 8),
                    const _Scrubber(),
                    const SizedBox(height: 20),
                    _MainControls(playing: state?.playing ?? false),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.album,
    required this.onQueue,
  });

  final String album;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 32),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PLAYING FROM',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music, size: 24),
            onPressed: onQueue,
            tooltip: 'Up next',
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Draggable strip so vertical scroll in the list still works.
class _DraggableTopStrip extends StatefulWidget {
  const _DraggableTopStrip({required this.child});
  final Widget child;

  @override
  State<_DraggableTopStrip> createState() => _DraggableTopStripState();
}

class _DraggableTopStripState extends State<_DraggableTopStrip> {
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) {
            if (d.primaryDelta == null) return;
            if (d.primaryDelta! > 0) {
              setState(() {
                _dy += d.primaryDelta!;
                _dy = _dy.clamp(0, 400);
              });
            } else {
              if (_dy > 0) {
                setState(() {
                  _dy = (_dy + d.primaryDelta!).clamp(0, 400);
                });
              }
            }
          },
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (_dy > 88 || v > 700) {
              if (context.mounted) {
                HapticFeedback.lightImpact();
                context.pop();
              }
            } else {
              setState(() => _dy = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _dy),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class _SecondaryControlsRow extends ConsumerWidget {
  const _SecondaryControlsRow({required this.mediaItem});
  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(playerLoopModeProvider).when(
          data: (v) => v,
          error: (_, __) => LoopMode.off,
          loading: () => LoopMode.off,
        );
    final shuffled = ref.watch(playerShuffleEnabledProvider).when(
          data: (v) => v,
          error: (_, __) => false,
          loading: () => false,
        );
    final fav = ref.watch(nowPlayingFavoriteProvider);
    final controller = ref.read(playerControllerProvider);
    final offline = mediaItem.extras?['isOffline'] == true;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => controller.toggleShuffle(),
          icon: Icon(
            Icons.shuffle,
            color: shuffled ? AppColors.primary : AppColors.textSecondary,
            size: 24,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => controller.cycleRepeatMode(),
          icon: Icon(
            loop == LoopMode.one ? Icons.repeat_one : Icons.repeat,
            color: loop == LoopMode.off
                ? AppColors.textSecondary
                : AppColors.primary,
            size: 26,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: offline
              ? null
              : () => ref.read(nowPlayingFavoriteProvider.notifier).toggle(),
          icon: _FavoriteHeartIcon(value: fav),
        ),
      ],
    );
  }
}

class _FavoriteHeartIcon extends StatelessWidget {
  const _FavoriteHeartIcon({required this.value});
  final AsyncValue<bool?> value;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (v) {
        if (v == null) {
          return const Icon(Icons.favorite_border, color: AppColors.textTertiary, size: 28);
        }
        return Icon(
          v ? Icons.favorite : Icons.favorite_border,
          color: v ? const Color(0xFFE85D75) : AppColors.textSecondary,
          size: 28,
        );
      },
      error: (_, __) => const Icon(Icons.heart_broken, color: AppColors.textTertiary, size: 28),
      loading: () => const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _VolumeRow extends ConsumerWidget {
  const _VolumeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(playerVolumeProvider).when(
          data: (v) => v.clamp(0.0, 1.0),
          error: (_, __) => 1.0,
          loading: () => 1.0,
        );
    final muted = ref.watch(audioHandlerProvider).isEffectivelyMuted;
    final controller = ref.read(playerControllerProvider);
    return Row(
      children: [
        IconButton(
          icon: Icon(
            muted ? Icons.volume_off : (v < 0.2 ? Icons.volume_mute : Icons.volume_up),
            color: AppColors.textSecondary,
            size: 22,
          ),
          onPressed: () => controller.toggleMute(),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.textPrimary,
              inactiveTrackColor: AppColors.divider,
              thumbColor: AppColors.textPrimary,
            ),
            child: Slider(
              value: v,
              min: 0,
              max: 1,
              onChanged: (x) {
                if (muted && x > 0) {
                  // setVolume in handler also unmutes
                }
                controller.setVolume(x);
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _Scrubber extends ConsumerWidget {
  const _Scrubber();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration =
        ref.watch(currentMediaItemProvider).value?.duration ?? Duration.zero;

    final clamped = position > duration ? duration : position;
    final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: AppColors.textPrimary,
            inactiveTrackColor: AppColors.divider,
            thumbColor: AppColors.textPrimary,
          ),
          child: Slider(
            value: clamped.inMilliseconds.toDouble().clamp(0, max),
            min: 0,
            max: max,
            onChanged: (x) => ref
                .read(playerControllerProvider)
                .seek(Duration(milliseconds: x.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(clamped),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              Text(
                formatDuration(duration),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MainControls extends ConsumerWidget {
  const _MainControls({required this.playing});
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous, color: AppColors.textPrimary),
          onPressed: controller.previous,
        ),
        const SizedBox(width: 20),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.textPrimary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33333333),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: IconButton(
            iconSize: 40,
            padding: const EdgeInsets.all(12),
            icon: Icon(
              playing ? Icons.pause : Icons.play_arrow,
              color: AppColors.background,
            ),
            onPressed: controller.togglePlay,
          ),
        ),
        const SizedBox(width: 20),
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_next, color: AppColors.textPrimary),
          onPressed: controller.next,
        ),
      ],
    );
  }
}
