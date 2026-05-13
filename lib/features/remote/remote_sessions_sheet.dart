import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/jellyfin/models/remote_session.dart';
import 'package:altsound/data/jellyfin/remote_sessions_repository.dart';
import 'package:altsound/features/player/player_providers.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';

final _sessionsListProvider = FutureProvider.autoDispose<List<RemoteSession>>((
  ref,
) {
  return ref.watch(remoteSessionsRepositoryProvider).list();
});

Future<void> showRemoteSessionsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _RemoteSessionsSheet(),
  );
}

class _RemoteSessionsSheet extends ConsumerWidget {
  const _RemoteSessionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_sessionsListProvider);
    final activeId = ref.watch(activeRemoteSessionIdProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Play on', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            if (activeId != null)
              ListTile(
                leading: const Icon(Icons.phone_android_rounded),
                title: const Text('This device'),
                onTap: () => _switchToLocal(context, ref, activeId),
              ),
            async.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text('No other devices available.'),
                  );
                }
                return Column(
                  children: [
                    for (final s in sessions)
                      ListTile(
                        leading: const Icon(Icons.cast_rounded),
                        title: Text(s.deviceName),
                        subtitle: Text(s.client),
                        trailing: s.id == activeId
                            ? const Icon(
                                Icons.check_rounded,
                                color: AppColors.like,
                              )
                            : null,
                        onTap: () => _switchToRemote(context, ref, s.id),
                      ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text('Couldn\'t load devices: $e'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hands off the local queue to [sessionId]: pauses local, sends `PlayNow` for
/// every queue item from the current index forward.
Future<void> _switchToRemote(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
) async {
  final navigator = Navigator.of(context);
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
  if (navigator.mounted) navigator.pop();
}

/// Stops the remote (so we don't leave it playing into the void) and switches
/// the app back to local control. Local queue is left untouched.
Future<void> _switchToLocal(
  BuildContext context,
  WidgetRef ref,
  String activeRemoteId,
) async {
  final navigator = Navigator.of(context);
  final repo = ref.read(remoteSessionsRepositoryProvider);
  try {
    await repo.stop(activeRemoteId);
  } catch (_) {
    // The remote may already be unreachable; clearing local state is what
    // matters most here.
  }
  ref.read(activeRemoteSessionIdProvider.notifier).clear();
  if (navigator.mounted) navigator.pop();
}
