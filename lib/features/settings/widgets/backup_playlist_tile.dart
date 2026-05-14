import 'package:flutter/material.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/playlists/playlist_backup_repository.dart';

/// Expansion tile listing the tracks inside one playlist of a backup.
class BackupPlaylistTile extends StatelessWidget {
  const BackupPlaylistTile({required this.playlist, super.key});

  final PlaylistBackupPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.queue_music_rounded),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${playlist.tracks.length} songs · ${_formatDuration(Duration(milliseconds: playlist.durationMs))}',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      children: [
        if (playlist.tracks.isEmpty)
          const ListTile(
            title: Text('No songs saved'),
            contentPadding: EdgeInsets.only(left: 72, right: AppSpacing.md),
          )
        else
          for (final track in playlist.tracks)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(
                left: 72,
                right: AppSpacing.md,
              ),
              title: Text(
                '${track.position}. ${track.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (track.artistText.isNotEmpty) track.artistText,
                  if (track.album != null && track.album!.isNotEmpty)
                    track.album!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: track.jellyfinTrackId == null
                  ? const Icon(
                      Icons.link_off_rounded,
                      color: AppColors.textTertiary,
                      size: 18,
                    )
                  : null,
            ),
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
