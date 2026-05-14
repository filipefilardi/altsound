import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';

class PlaylistsHeader extends StatelessWidget {
  const PlaylistsHeader({required this.onCreatePlaylist, super.key});

  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'PLAYLISTS',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            onPressed: onCreatePlaylist,
            icon: const Icon(PhosphorIconsRegular.plus, size: 20),
            color: AppColors.primary,
            visualDensity: VisualDensity.compact,
            tooltip: 'New playlist',
          ),
        ],
      ),
    );
  }
}
