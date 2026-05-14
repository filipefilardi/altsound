import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
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
        ListTile(
          leading: const Icon(PhosphorIconsRegular.monitorPlay),
          title: const Text('Streaming quality'),
          subtitle: Text(
            prefs.streamingQuality.label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          onTap: () => _showStreamingQualitySheet(context),
        ),
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

Future<void> _showStreamingQualitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playbackPreferencesProvider).streamingQuality;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Streaming quality',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                RadioGroup<StreamingQuality>(
                  groupValue: current,
                  onChanged: (v) async {
                    if (v == null) return;
                    await ref
                        .read(playbackPreferencesProvider.notifier)
                        .setStreamingQuality(v);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Column(
                    children: [
                      for (final q in StreamingQuality.values)
                        RadioListTile<StreamingQuality>(
                          value: q,
                          title: Text(q.label),
                          subtitle: Text(
                            q.subtitle,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
