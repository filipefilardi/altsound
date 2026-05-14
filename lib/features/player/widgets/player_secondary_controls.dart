import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/features/player/current_track_playlist_presence.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/player/widgets/add_track_to_playlist_sheet.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';

/// Secondary control row on the now-playing screen: shuffle, repeat, instant
/// mix, and "add to playlist". Items are disabled when remote/syncplay mode
/// owns playback.
class PlayerSecondaryControls extends ConsumerWidget {
  const PlayerSecondaryControls({required this.mediaItem, super.key});
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
            PhosphorIconsRegular.shuffle,
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
                ? PhosphorIconsRegular.repeatOnce
                : PhosphorIconsRegular.repeat,
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
            PhosphorIconsRegular.sparkle,
            color: AppColors.textSecondary,
            size: 22,
          ),
          tooltip: 'Instant Mix',
        ),
        IconButton(
          onPressed: offline || isRemote
              ? null
              : () => unawaited(
                  _onPlaylistTap(context, ref, trackId: mediaItem.id),
                ),
          icon: Icon(
            saved ? PhosphorIconsRegular.listChecks : PhosphorIconsRegular.listPlus,
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
}) async {
  await openManageTrackPlaylistsSheet(context, ref, trackId: trackId);
  ref.invalidate(currentTrackPlaylistPresenceProvider);
}
