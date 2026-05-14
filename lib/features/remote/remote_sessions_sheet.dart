import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/data/jellyfin/models/remote_session.dart';
import 'package:altsound/data/jellyfin/remote_sessions_repository.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';

final _sessionsListProvider = FutureProvider.autoDispose<List<RemoteSession>>((
  ref,
) {
  return ref.watch(remoteSessionsRepositoryProvider).list();
});

/// Opens the "Play on…" device picker as a floating glass popover anchored
/// to [context] (the cast icon in the header).
Future<void> showRemoteSessionsPopover(BuildContext context) {
  return showGlassPopover<void>(
    context: context,
    width: 300,
    builder: (_) => const _RemoteSessionsPopover(),
  );
}

class _RemoteSessionsPopover extends ConsumerWidget {
  const _RemoteSessionsPopover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_sessionsListProvider);
    final activeId = ref.watch(activeRemoteSessionIdProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlassPopoverHeader(label: 'PLAY ON'),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeId != null)
                  GlassPopoverItem(
                    icon: PhosphorIconsRegular.deviceMobile,
                    label: 'This device',
                    onTap: () => _switchToLocal(ref, activeId),
                  ),
                async.when(
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'No other devices available.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in sessions)
                          GlassPopoverItem(
                            icon: PhosphorIconsRegular.screencast,
                            label: s.deviceName,
                            subtitle: s.client,
                            trailing: s.id == activeId
                                ? const Icon(
                                    PhosphorIconsRegular.check,
                                    size: 18,
                                    color: AppColors.like,
                                  )
                                : null,
                            onTap: () => _switchToRemote(ref, s.id),
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      "Couldn't load devices: $e",
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// Hands off the local queue to [sessionId]: pauses local, sends `PlayNow` for
/// every queue item from the current index forward.
Future<void> _switchToRemote(WidgetRef ref, String sessionId) async {
  final handler = ref.read(audioHandlerProvider);
  final repo = ref.read(remoteSessionsRepositoryProvider);

  final queue = handler.queue.value;
  final currentItem = handler.mediaItem.value;
  final currentIndex = currentItem == null
      ? -1
      : queue.indexWhere((m) => m.id == currentItem.id);
  final tail = currentIndex >= 0 ? queue.sublist(currentIndex) : queue;

  ref.read(activeRemoteSessionIdProvider.notifier).set(sessionId);
  if (handler.playbackState.value.playing) await handler.pause();
  if (tail.isNotEmpty) {
    await repo.playItems(sessionId, tail.map((m) => m.id).toList());
  }
}

/// Stops the remote (so we don't leave it playing into the void) and switches
/// the app back to local control. Local queue is left untouched.
Future<void> _switchToLocal(WidgetRef ref, String activeRemoteId) async {
  final repo = ref.read(remoteSessionsRepositoryProvider);
  try {
    await repo.stop(activeRemoteId);
  } catch (_) {
    // The remote may already be unreachable; clearing local state is what
    // matters most here.
  }
  ref.read(activeRemoteSessionIdProvider.notifier).clear();
}
