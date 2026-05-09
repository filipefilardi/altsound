import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../core/utils/format.dart';
import '../remote/remote_player_controller.dart';
import '../syncplay/syncplay_controller.dart';
import 'audio_player_handler.dart';
import 'current_track_playlist_presence.dart';
import 'instant_mix.dart';
import 'player_providers.dart';
import 'widgets/add_track_to_playlist_sheet.dart';
import 'widgets/player_hero_art.dart';
import 'widgets/queue_bottom_sheet.dart';

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
                    _TopBar(
                      album: mediaItem.album ?? '',
                      albumId: albumId,
                      onQueue: () => showQueueBottomSheet(context, ref),
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
                              const SizedBox(height: 28),
                              Text(
                                mediaItem.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 6),
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
                      _ErrorBanner(
                        error: _error!,
                        onSkip: () {
                          ref.read(playerControllerProvider).next();
                          setState(() => _error = null);
                        },
                        onDismiss: () => setState(() => _error = null),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _SecondaryControls(mediaItem: mediaItem),
                    const SizedBox(height: 12),
                    const PlayerScrubber(),
                    const SizedBox(height: 16),
                    _MainControls(playing: playing),
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

/// Wraps the now-playing surface with a vertical-drag-to-dismiss gesture.
///
/// The whole surface is draggable: drag down, the screen translates with the
/// finger, and on release we either pop (past threshold or fast flick) or
/// snap back. Doesn't fight any inner scrollables because the now-playing
/// layout is a non-scrolling [Column].
class PlayerDismissibleSurface extends StatefulWidget {
  const PlayerDismissibleSurface({required this.child, super.key});
  final Widget child;

  @override
  State<PlayerDismissibleSurface> createState() =>
      _PlayerDismissibleSurfaceState();
}

class _PlayerDismissibleSurfaceState extends State<PlayerDismissibleSurface>
    with SingleTickerProviderStateMixin {
  double _dy = 0;
  late final AnimationController _settle;
  Animation<double>? _settleAnim;

  @override
  void initState() {
    super.initState();
    // Eager init: a lazy field initializer would run on first read; if that
    // first read is dispose(), vsync looks up TickerMode on a deactivated element.
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_onSettleTick);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    if (_settleAnim != null) {
      setState(() => _dy = _settleAnim!.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final dismissThreshold = screenH * 0.18;
    final progress = (_dy / (screenH * 0.6)).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _settle.stop();
      },
      onVerticalDragUpdate: (d) {
        final delta = d.primaryDelta ?? 0;
        if (delta == 0) return;
        setState(() {
          _dy = (_dy + delta).clamp(0.0, screenH);
        });
      },
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dy > dismissThreshold || v > 700) {
          HapticFeedback.lightImpact();
          context.pop();
        } else {
          _settleAnim = Tween<double>(begin: _dy, end: 0).animate(
            CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
          );
          _settle.forward(from: 0);
        }
      },
      child: Opacity(
        opacity: 1 - progress * 0.6,
        child: Transform.translate(offset: Offset(0, _dy), child: widget.child),
      ),
    );
  }
}

class PlayerDragHandle extends StatelessWidget {
  const PlayerDragHandle({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textTertiary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class PlayerBackdrop extends StatelessWidget {
  const PlayerBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(decoration: BoxDecoration(color: AppColors.surface)),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.album,
    required this.albumId,
    required this.onQueue,
  });
  final String album;
  final String? albumId;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteId = ref.watch(activeRemoteSessionIdProvider);
    final remoteSession = remoteId == null
        ? null
        : ref.watch(activeRemoteSessionProvider).value;
    final syncGroup = ref.watch(syncPlayControllerProvider).activeGroup;
    final castConnected = remoteId != null;
    final castLabel = castConnected
        ? 'PLAYING ON ${remoteSession?.deviceName.toUpperCase() ?? 'REMOTE'}'
        : syncGroup != null
        ? 'SYNCPLAY: ${syncGroup.name.toUpperCase()}'
        : 'PLAYING FROM ALBUM';
    // Reserve symmetric space on both sides so the centered text is not
    // pushed off-center by edge icons (one icon per side, ~48 px each).
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
                        castLabel,
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
                        onTap:
                            albumId == null || albumId!.isEmpty || album.isEmpty
                            ? null
                            : () => context.push('/album/$albumId'),
                        child: Text(
                          album,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                albumId == null ||
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                  onPressed: () => context.pop(),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.queue_music_rounded, size: 24),
                      onPressed: onQueue,
                      tooltip: 'Up next',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryControls extends ConsumerWidget {
  const _SecondaryControls({required this.mediaItem});
  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRemote = ref.watch(activeRemoteSessionIdProvider) != null;
    final isSyncPlay =
        ref.watch(syncPlayControllerProvider).activeGroup != null;
    final loop = ref
        .watch(playerLoopModeProvider)
        .when(
          data: (v) => v,
          error: (_, __) => LoopMode.off,
          loading: () => LoopMode.off,
        );
    final shuffled = ref
        .watch(playerShuffleEnabledProvider)
        .when(data: (v) => v, error: (_, __) => false, loading: () => false);
    final controller = ref.read(playerControllerProvider);
    final offline = mediaItem.extras?['isOffline'] == true;
    final presenceAsync = ref.watch(currentTrackPlaylistPresenceProvider);
    final saved = switch (presenceAsync) {
      AsyncData(:final value) => value.memberships.isNotEmpty,
      _ => false,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: isRemote || isSyncPlay
              ? null
              : () => controller.toggleShuffle(),
          icon: Icon(
            Icons.shuffle_rounded,
            color: shuffled ? AppColors.primary : AppColors.textSecondary,
            size: 22,
          ),
          tooltip: 'Shuffle',
        ),
        IconButton(
          onPressed: isRemote || isSyncPlay
              ? null
              : () => controller.cycleRepeatMode(),
          icon: Icon(
            loop == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: loop == LoopMode.off
                ? AppColors.textSecondary
                : AppColors.primary,
            size: 22,
          ),
          tooltip: 'Repeat',
        ),
        IconButton(
          onPressed: () => openInstantMixPage(
            context,
            ref,
            itemId: mediaItem.id,
            kind: InstantMixSeedKind.track,
            title: mediaItem.title,
          ),
          icon: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.textSecondary,
            size: 22,
          ),
          tooltip: 'Instant Mix',
        ),
        IconButton(
          onPressed: offline || isRemote
              ? null
              : () => unawaited(
                  _onPlaylistTap(
                    context,
                    ref,
                    trackId: mediaItem.id,
                    saved: saved,
                  ),
                ),
          icon: Icon(
            saved
                ? Icons.playlist_add_check_rounded
                : Icons.playlist_add_rounded,
            color: saved ? AppColors.primary : AppColors.textSecondary,
            size: 24,
          ),
          tooltip: 'Add to playlist',
        ),
      ],
    );
  }
}

Future<void> _onPlaylistTap(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required bool saved,
}) async {
  await openManageTrackPlaylistsSheet(context, ref, trackId: trackId);
  ref.invalidate(currentTrackPlaylistPresenceProvider);
}

class PlayerScrubber extends ConsumerWidget {
  const PlayerScrubber({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(effectivePositionProvider);
    final duration = ref.watch(effectiveDurationProvider);

    final clamped = position > duration ? duration : position;
    final maxMs = duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final value = clamped.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: AppColors.primary,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: maxMs,
            onChanged: (x) => ref
                .read(playerControllerProvider)
                .seek(Duration(milliseconds: x.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(clamped),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                formatDuration(duration),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
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
          icon: const Icon(
            Icons.skip_previous_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: controller.previous,
        ),
        const SizedBox(width: 24),
        PlayerPlayPauseButton(playing: playing, onTap: controller.togglePlay),
        const SizedBox(width: 24),
        IconButton(
          iconSize: 32,
          icon: const Icon(
            Icons.skip_next_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: controller.next,
        ),
      ],
    );
  }
}

class PlayerPlayPauseButton extends StatelessWidget {
  const PlayerPlayPauseButton({
    required this.playing,
    required this.onTap,
    super.key,
  });
  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: AppGradients.accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppColors.onAccent,
              size: 36,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.error,
    required this.onSkip,
    required this.onDismiss,
  });
  final PlayerError error;
  final VoidCallback onSkip;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Skip'),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
