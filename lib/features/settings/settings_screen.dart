import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_gradients.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/jellyfin/jellyfin_repository.dart';
import '../../data/jellyfin/models/jellyfin_session.dart';
import '../../data/local/playback_preferences.dart';
import '../auth/auth_controller.dart';

final _serverInfoProvider = FutureProvider.autoDispose<JellyfinServerInfo?>(
  (ref) => ref.watch(jellyfinRepositoryProvider).serverInfo(),
);

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

final _imageCacheSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/libCachedImageData');
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          /* skip unreadable */
        }
      }
    }
    return total;
  } catch (_) {
    return 0;
  }
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final session = auth is AuthAuthenticated ? auth.session : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          if (session != null) ...[
            _AccountCard(session: session),
            const SizedBox(height: 28),
          ],
          const _PlaybackGroup(),
          const SizedBox(height: 24),
          const _LibraryGroup(),
          const SizedBox(height: 24),
          const _StorageGroup(),
          const SizedBox(height: 28),
          const _SignOutTile(),
          const SizedBox(height: 28),
          const _VersionFooter(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.session});

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
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showAccountSheet(context, session),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _Avatar(name: session.username),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusDot(online: online),
                        const SizedBox(width: 6),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Account',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

class _PlaybackGroup extends ConsumerWidget {
  const _PlaybackGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(playbackPreferencesProvider);
    return _SettingsGroup(
      label: 'Playback',
      children: [
        ListTile(
          leading: const Icon(Icons.high_quality_rounded),
          title: const Text('Streaming quality'),
          subtitle: Text(
            prefs.streamingQuality.label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          onTap: () => _showStreamingQualitySheet(context),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.swap_horiz_rounded),
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

class _LibraryGroup extends ConsumerWidget {
  const _LibraryGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);

    return _SettingsGroup(
      label: 'Library',
      children: [
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: const Text('Downloads'),
          subtitle: Text(
            '${downloads.tracks.length} tracks · ${_formatBytes(downloads.totalSizeBytes)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          onTap: () => context.push('/downloads'),
        ),
        ListTile(
          leading: const Icon(Icons.tune_rounded),
          title: const Text('Download settings'),
          subtitle: const Text(
            'Auto-download, WiFi only',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          onTap: () => context.push('/settings/downloads'),
        ),
      ],
    );
  }
}

class _StorageGroup extends ConsumerWidget {
  const _StorageGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(_imageCacheSizeProvider);
    return _SettingsGroup(
      label: 'Storage',
      children: [
        ListTile(
          leading: const Icon(Icons.image_rounded),
          title: const Text('Clear image cache'),
          subtitle: Text(
            size.when(
              data: (b) => b == 0 ? 'Empty' : _formatBytes(b),
              loading: () => '…',
              error: (_, __) => '—',
            ),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          enabled: size.maybeWhen(data: (b) => b > 0, orElse: () => false),
          onTap: () async {
            await DefaultCacheManager().emptyCache();
            ref.invalidate(_imageCacheSizeProvider);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image cache cleared')),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sign out / version
// ---------------------------------------------------------------------------

class _SignOutTile extends ConsumerWidget {
  const _SignOutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.logout_rounded, color: AppColors.error),
        title: const Text('Sign out', style: TextStyle(color: AppColors.error)),
        onTap: () async {
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) context.pop();
        },
      ),
    );
  }
}

class _VersionFooter extends ConsumerWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pkg = ref.watch(_packageInfoProvider);
    return Center(
      child: Text(
        pkg.when(
          data: (p) => 'AltSound ${p.version}',
          loading: () => 'AltSound',
          error: (_, __) => 'AltSound',
        ),
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheets
// ---------------------------------------------------------------------------

Future<void> _showStreamingQualitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playbackPreferencesProvider).streamingQuality;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Streaming quality',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
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

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i < children.length - 1) {
        tiles.add(const Divider(height: 1, indent: 56));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
}
