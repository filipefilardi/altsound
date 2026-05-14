import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:altsound/core/theme/app_colors.dart';
import 'package:altsound/core/theme/app_gradients.dart';
import 'package:altsound/core/theme/app_radius.dart';
import 'package:altsound/core/theme/app_spacing.dart';
import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/jellyfin_session.dart';

final _serverInfoProvider = FutureProvider.autoDispose<JellyfinServerInfo?>(
  (ref) => ref.watch(jellyfinRepositoryProvider).serverInfo(),
);

/// Top card on the settings screen: shows the signed-in user, avatar, server
/// URL and reachability status. Tapping opens a bottom sheet with the full
/// account / server details (server name, version).
class AccountCard extends ConsumerWidget {
  const AccountCard({required this.session, super.key});

  final JellyfinSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(_serverInfoProvider);
    final bool? online = info.when(
      data: (i) => i != null,
      loading: () => null,
      error: (_, __) => false,
    );

    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showAccountSheet(context, session),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              _Avatar(name: session.username),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.username,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        _StatusDot(online: online),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            session.serverUrl,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        gradient: AppGradients.accent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: const TextStyle(
          color: AppColors.onAccent,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online});

  /// `null` while we're still checking.
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final color = online == null
        ? AppColors.textTertiary
        : online!
        ? const Color(0xFF66CC8A)
        : AppColors.error;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showAccountSheet(BuildContext context, JellyfinSession session) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final info = ref.watch(_serverInfoProvider);
        String infoValue(String? Function(JellyfinServerInfo i) extract) {
          return info.when(
            data: (i) => i == null ? 'Unreachable' : (extract(i) ?? '—'),
            loading: () => 'Checking…',
            error: (_, __) => 'Unreachable',
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Account',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                _DetailRow(label: 'User', value: session.username),
                _DetailRow(label: 'Server', value: session.serverUrl),
                _DetailRow(
                  label: 'Server name',
                  value: infoValue((i) => i.serverName),
                ),
                _DetailRow(
                  label: 'Server version',
                  value: infoValue((i) => i.version),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
