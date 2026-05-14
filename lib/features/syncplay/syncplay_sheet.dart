import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/core/widgets/glass_popover.dart';
import 'package:altsound/features/remote/remote_player_controller.dart';
import 'package:altsound/features/syncplay/syncplay_controller.dart';

/// Shows the SyncPlay menu as a floating glass popover anchored to [context]
/// (typically the SyncPlay icon in the header).
Future<void> showSyncPlayPopover(BuildContext context) {
  return showGlassPopover<void>(
    context: context,
    width: 300,
    builder: (_) => const _SyncPlayPopover(),
  );
}

class _SyncPlayPopover extends ConsumerStatefulWidget {
  const _SyncPlayPopover();

  @override
  ConsumerState<_SyncPlayPopover> createState() => _SyncPlayPopoverState();
}

class _SyncPlayPopoverState extends ConsumerState<_SyncPlayPopover> {
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

    final Widget body;
    if (remoteActive) {
      body = _buildRemoteActive();
    } else if (state.activeGroup != null) {
      body = _buildActiveGroup(state, controller);
    } else {
      body = _buildJoinGroup(state, controller);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GlassPopoverHeader(label: 'SYNCPLAY'),
        Flexible(child: SingleChildScrollView(child: body)),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              state.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }

  Widget _buildRemoteActive() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Text(
        'Switch back to this device to use SyncPlay.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }

  Widget _buildJoinGroup(SyncPlayState state, SyncPlayController controller) {
    if (state.loading && state.groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in state.groups)
          GlassPopoverItem(
            icon: Icons.person_rounded,
            label: group.name,
            subtitle: group.participants.isEmpty
                ? 'No users connected'
                : group.participants.join(', '),
            enabled: !state.loading,
            onTap: () => controller.joinGroup(group.id),
          ),
        GlassPopoverItem(
          icon: Icons.add_rounded,
          label: 'New group',
          subtitle: 'Create a new group',
          enabled: !state.loading,
          onTap: () => controller.createGroup(''),
        ),
      ],
    );
  }

  Widget _buildActiveGroup(SyncPlayState state, SyncPlayController controller) {
    final group = state.activeGroup!;
    final participants = group.participants.isEmpty
        ? 'No users connected'
        : group.participants.join(', ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                participants,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        GlassPopoverItem(
          icon: Icons.logout_rounded,
          label: 'Leave group',
          subtitle: 'Disable SyncPlay',
          destructive: true,
          onTap: controller.leaveGroup,
        ),
      ],
    );
  }
}
