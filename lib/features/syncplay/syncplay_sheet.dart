import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';

Future<void> showSyncPlaySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _SyncPlaySheet(),
  );
}

class _SyncPlaySheet extends ConsumerStatefulWidget {
  const _SyncPlaySheet();

  @override
  ConsumerState<_SyncPlaySheet> createState() => _SyncPlaySheetState();
}

class _SyncPlaySheetState extends ConsumerState<_SyncPlaySheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncPlayControllerProvider.notifier).refreshGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncPlayControllerProvider);
    final controller = ref.read(syncPlayControllerProvider.notifier);
    final remoteActive = ref.watch(activeRemoteSessionIdProvider) != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (remoteActive)
              _buildRemoteActive(context)
            else if (state.activeGroup != null)
              _buildActiveGroup(context, state, controller)
            else
              _buildJoinGroup(context, state, controller),
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                state.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteActive(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SyncPlay', style: Theme.of(context).textTheme.titleLarge),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text('Switch back to this device to use SyncPlay.'),
        ),
      ],
    );
  }

  Widget _buildJoinGroup(
    BuildContext context,
    SyncPlayState state,
    SyncPlayController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Join a group', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        if (state.loading && state.groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final group in state.groups)
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text(group.name),
              subtitle: Text(
                group.participants.isEmpty
                    ? 'No users connected'
                    : group.participants.join(', '),
              ),
              onTap: state.loading
                  ? null
                  : () async {
                      await controller.joinGroup(group.id);
                      if (!context.mounted) return;
                      final joined =
                          ref.read(syncPlayControllerProvider).activeGroup !=
                          null;
                      if (joined) Navigator.of(context).pop();
                    },
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New group'),
            subtitle: const Text('Create a new group'),
            onTap: state.loading
                ? null
                : () async {
                    await controller.createGroup('');
                    if (!context.mounted) return;
                    final joined =
                        ref.read(syncPlayControllerProvider).activeGroup !=
                        null;
                    if (joined) Navigator.of(context).pop();
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildActiveGroup(
    BuildContext context,
    SyncPlayState state,
    SyncPlayController controller,
  ) {
    final group = state.activeGroup!;
    final participants = group.participants.isEmpty
        ? 'No users connected'
        : group.participants.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(group.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          participants,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout_rounded),
          title: const Text('Leave group'),
          subtitle: const Text('Disable SyncPlay'),
          onTap: () async {
            Navigator.of(context).pop();
            await controller.leaveGroup();
          },
        ),
      ],
    );
  }
}
