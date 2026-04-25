import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/lidarr/lidarr_repository.dart';
import '../../data/lidarr/models/lidarr_models.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadManagerProvider);
    final lidarr = ref.watch(lidarrRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _SectionTile(
            icon: Icons.download_outlined,
            title: 'Downloads',
            subtitle: downloads.tracks.isEmpty
                ? 'Tap an album\'s download icon to keep it offline'
                : '${downloads.tracks.length} tracks',
            onTap: () => context.push('/downloads'),
          ),
          if (lidarr != null)
            _LidarrMonitoredSection(repo: lidarr)
          else
            _SectionTile(
              icon: Icons.travel_explore_outlined,
              title: 'Connect Lidarr',
              subtitle: 'Search and request new music to add to your library',
              onTap: () => context.push('/settings/lidarr'),
            ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: AppColors.textPrimary),
      ),
      title: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}

class _LidarrMonitoredSection extends StatefulWidget {
  const _LidarrMonitoredSection({required this.repo});
  final LidarrRepository repo;

  @override
  State<_LidarrMonitoredSection> createState() =>
      _LidarrMonitoredSectionState();
}

class _LidarrMonitoredSectionState extends State<_LidarrMonitoredSection> {
  late Future<List<LidarrArtistResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.monitoredArtists();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LidarrArtistResult>>(
      future: _future,
      builder: (context, snap) {
        final count = snap.data?.length;
        return _SectionTile(
          icon: Icons.queue_music_outlined,
          title: 'Lidarr requests',
          subtitle: snap.connectionState == ConnectionState.waiting
              ? 'Loading…'
              : (count == null
                  ? 'Discover and request music via Lidarr'
                  : '$count monitored artists'),
          onTap: () => context.push('/discover'),
        );
      },
    );
  }
}
