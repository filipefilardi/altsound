import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/jellyfin/auth_repository.dart';
import '../remote/remote_player_controller.dart';
import 'syncplay_controller.dart';

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
  final _name = TextEditingController();
  bool _suggestedNameApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncPlayControllerProvider.notifier).refreshGroups();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(syncPlayControllerProvider);
    final controller = ref.read(syncPlayControllerProvider.notifier);
    final remoteActive = ref.watch(activeRemoteSessionIdProvider) != null;
    final username = ref.watch(jellyfinApiProvider).session?.username;
    if (!_suggestedNameApplied && username != null && username.isNotEmpty) {
      _suggestedNameApplied = true;
      _name.text = "$username's group";
    }

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
            Text('SyncPlay', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (remoteActive)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Switch back to this device to use SyncPlay.'),
              )
            else if (state.activeGroup != null) ...[
              ListTile(
                leading: const Icon(
                  Icons.groups_rounded,
                  color: AppColors.primary,
                ),
                title: Text(state.activeGroup!.name),
                subtitle: Text(
                  '${state.activeGroup!.participants.length} participant${state.activeGroup!.participants.length == 1 ? '' : 's'}',
                ),
                trailing: TextButton(
                  onPressed: () => controller.leaveGroup(),
                  child: const Text('Leave'),
                ),
              ),
              if (state.activeGroup!.participants.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final participant in state.activeGroup!.participants)
                      Chip(
                        avatar: const Icon(Icons.person_rounded, size: 16),
                        label: Text(participant),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => controller.createGroup(_name.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: state.loading
                        ? null
                        : () => controller.createGroup(_name.text),
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Create group',
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.connected ? 'Connected' : 'Connecting…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  onPressed: state.loading ? null : controller.refreshGroups,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            if (state.loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!remoteActive && state.groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No groups available.'),
              )
            else if (!remoteActive)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final group in state.groups)
                      ListTile(
                        leading: Icon(
                          state.activeGroup?.id == group.id
                              ? Icons.check_circle_rounded
                              : Icons.groups_rounded,
                          color: state.activeGroup?.id == group.id
                              ? AppColors.primary
                              : null,
                        ),
                        title: Text(group.name),
                        subtitle: Text(
                          group.participants.isEmpty
                              ? 'No users connected'
                              : group.participants.join(', '),
                        ),
                        onTap: state.activeGroup?.id == group.id
                            ? null
                            : () => controller.joinGroup(group.id),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
