import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/widgets/settings_group.dart';
import 'package:altsound/data/local/playback_preferences.dart';

class PlaybackGroup extends ConsumerWidget {
  const PlaybackGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(playbackPreferencesProvider);
    return SettingsGroup(
      label: 'Playback',
      children: [
        SwitchListTile(
          secondary: const Icon(PhosphorIconsRegular.arrowsLeftRight),
          title: const Text('Gapless playback'),
          subtitle: const Text(
            'Eagerly preload tracks for seamless transitions. Applies on next launch.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          value: prefs.gaplessPlayback,
          onChanged: (v) => ref
              .read(playbackPreferencesProvider.notifier)
              .setGaplessPlayback(v),
        ),
      ],
    );
  }
}
