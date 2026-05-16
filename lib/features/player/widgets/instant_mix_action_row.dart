import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/core/widgets/media_action_row.dart';
import 'package:altsound/core/widgets/play_pill.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/features/player/instant_mix.dart';
import 'package:altsound/features/player/instant_mix_screen.dart'
    show instantMixTracksProvider;
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/playlist/playlist_providers.dart';

/// Horizontal action row for the Instant Mix detail screen:
/// Play, total-duration label, Shuffle, Regenerate (with spinner), and More
/// menu (Add to queue / Create playlist from mix).
class InstantMixActionRow extends ConsumerWidget {
  const InstantMixActionRow({
    required this.seedItemId,
    required this.seedKind,
    required this.seedTitle,
    required this.tracks,
    super.key,
  });

  final String seedItemId;
  final InstantMixSeedKind? seedKind;
  final String? seedTitle;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffleEnabled =
        ref.watch(playerShuffleEnabledProvider).value ?? false;
    final contextId = instantMixContextId(seedItemId);
    final isMixPlaying = ref.watch(isContextPlayingProvider(contextId));
    final hasTracks = tracks.isNotEmpty;
    final request = (itemId: seedItemId, kind: seedKind);
    final mixAsync = ref.watch(instantMixTracksProvider(request));
    final isRegenerating = mixAsync.isLoading && mixAsync.hasValue;

    return MediaActionRow(
      actions: [
        IconButton(
            tooltip: 'Shuffle',
            icon: Icon(
              PhosphorIconsRegular.shuffle,
              color: shuffleEnabled ? AppColors.primary : AppColors.textPrimary,
            ),
            onPressed: () => ref.read(playerControllerProvider).toggleShuffle(),
          ),
          IconButton(
            tooltip: isRegenerating ? 'Regenerating mix' : 'Regenerate mix',
            icon: isRegenerating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(PhosphorIconsRegular.arrowsClockwise),
            onPressed: isRegenerating
                ? null
                : () => ref.invalidate(instantMixTracksProvider(request)),
          ),
          Builder(
            builder: (anchorCtx) => IconButton(
              tooltip: 'More actions',
              icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
              onPressed: () =>
                  _showMoreActions(anchorCtx, context, ref, hasTracks),
            ),
          ),
      ],
      playControl: PlayPill(
        onTap: hasTracks
            ? () {
                final controller = ref.read(playerControllerProvider);
                if (isMixPlaying) {
                  controller.togglePlay();
                  return;
                }
                controller.playTracks(
                  tracks,
                  contextId: contextId,
                  randomizeStart: false,
                );
              }
            : null,
        icon: isMixPlaying
            ? PhosphorIconsFill.pause
            : PhosphorIconsFill.play,
        tooltip: isMixPlaying ? 'Pause' : 'Play',
      ),
    );
  }

  Future<void> _showMoreActions(
    BuildContext anchorCtx,
    BuildContext context,
    WidgetRef ref,
    bool hasTracks,
  ) {
    return showGlassPopover<void>(
      context: anchorCtx,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassPopoverItem(
            icon: PhosphorIconsRegular.listPlus,
            label: 'Add to queue',
            enabled: hasTracks,
            onTap: () => _addMixToQueue(context, ref, tracks),
          ),
          GlassPopoverItem(
            icon: PhosphorIconsRegular.listPlus,
            label: 'Create playlist from mix',
            enabled: hasTracks,
            onTap: () => _createPlaylistFromMix(
              context,
              ref,
              seedTitle: seedTitle,
              tracks: tracks,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

Future<void> _addMixToQueue(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  final added = await ref
      .read(playerControllerProvider)
      .addTracksToQueue(tracks);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Added $added song${added == 1 ? '' : 's'} to queue'),
    ),
  );
}

Future<void> _createPlaylistFromMix(
  BuildContext context,
  WidgetRef ref, {
  required String? seedTitle,
  required List<Track> tracks,
}) async {
  final defaultName = seedTitle == null || seedTitle.trim().isEmpty
      ? 'Instant Mix'
      : 'Instant Mix - ${seedTitle.trim()}';
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _CreateInstantMixPlaylistDialog(initialName: defaultName),
  );
  final playlistName = name?.trim();
  if (playlistName == null || playlistName.isEmpty || !context.mounted) return;

  try {
    final repo = ref.read(jellyfinRepositoryProvider);
    final playlist = await repo.createPlaylist(playlistName);
    await repo.addTracksToPlaylist(
      trackIds: tracks.map((track) => track.id).toList(),
      playlistId: playlist.id,
    );
    ref.invalidate(playlistProvider(playlist.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Created "${playlist.name}" with ${tracks.length} song${tracks.length == 1 ? '' : 's'}',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not create playlist: $e')));
  }
}

class _CreateInstantMixPlaylistDialog extends StatefulWidget {
  const _CreateInstantMixPlaylistDialog({required this.initialName});

  final String initialName;

  @override
  State<_CreateInstantMixPlaylistDialog> createState() =>
      _CreateInstantMixPlaylistDialogState();
}

class _CreateInstantMixPlaylistDialogState
    extends State<_CreateInstantMixPlaylistDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
