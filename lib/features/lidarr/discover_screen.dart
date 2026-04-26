import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/lidarr/lidarr_repository.dart';
import '../../data/lidarr/models/lidarr_models.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _term = '';
  late Future<List<LidarrArtistResult>> _resultsFuture;

  @override
  void initState() {
    super.initState();
    _resultsFuture = Future.value(const []);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final repo = ref.read(lidarrRepositoryProvider);
      if (repo == null) return;
      setState(() {
        _term = v.trim();
        _resultsFuture =
            _term.isEmpty ? Future.value(const []) : repo.searchArtists(_term);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(lidarrRepositoryProvider);

    if (repo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Discover')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.queue_music,
                    size: 72, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                Text('Connect Lidarr to discover music',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'Lidarr finds and downloads new artists and albums automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.push('/settings/lidarr'),
                  child: const Text('CONNECT LIDARR'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search artists to add to your library',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _term.isEmpty
                ? const EmptyState(
                    icon: Icons.travel_explore,
                    title: 'Find new artists',
                    message: 'Search to request artists to your Lidarr library.',
                  )
                : FutureBuilder<List<LidarrArtistResult>>(
                    future: _resultsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline,
                          title: 'Search failed',
                          message: '${snapshot.error}',
                        );
                      }
                      final results = snapshot.data ?? const [];
                      if (results.isEmpty) {
                        return const EmptyState(
                          icon: Icons.search_off,
                          title: 'No matches',
                          message: 'Try a different artist name.',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 80),
                        itemBuilder: (_, i) =>
                            _ArtistTile(artist: results[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist});
  final LidarrArtistResult artist;

  @override
  Widget build(BuildContext context) {
    final a = artist;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () => context.push('/discover/artist', extra: a),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 56,
          height: 56,
          child: a.imageUrl == null
              ? Container(
                  color: AppColors.surfaceElevated,
                  child: const Icon(Icons.person, color: AppColors.textTertiary),
                )
              : CachedNetworkImage(
                  imageUrl: a.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.surfaceElevated),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceElevated,
                    child: const Icon(Icons.person, color: AppColors.textTertiary),
                  ),
                ),
        ),
      ),
      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        a.albumCount == null ? (a.overview ?? 'Artist') : '${a.albumCount} albums',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: a.alreadyMonitored
          ? const Icon(Icons.check, color: AppColors.primary)
          : const Icon(Icons.chevron_right, color: AppColors.textTertiary),
    );
  }
}

