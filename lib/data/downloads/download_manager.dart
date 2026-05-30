import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:altsound/data/jellyfin/jellyfin_repository.dart';
import 'package:altsound/data/jellyfin/models/media_item.dart';
import 'package:altsound/data/downloads/download_preferences.dart';
import 'package:altsound/data/downloads/downloaded_playlist.dart';
import 'package:altsound/data/downloads/downloaded_track.dart';

class DownloadsState {
  const DownloadsState({
    this.tracks = const {},
    this.progress = const {},
    this.queueLength = 0,
    this.queuedTrackIds = const {},
    this.playlists = const {},
    this.isBlockedByWifiOnly = false,
  });

  final Map<String, DownloadedTrack> tracks;
  final Map<String, double> progress;
  final int queueLength;
  final Set<String> queuedTrackIds;
  final Map<String, DownloadedPlaylist> playlists;
  final bool isBlockedByWifiOnly;

  bool isDownloaded(String trackId) => tracks.containsKey(trackId);
  bool isQueued(String trackId) => queuedTrackIds.contains(trackId);
  double? progressFor(String trackId) => progress[trackId];

  int get totalSizeBytes => tracks.values.fold(0, (sum, t) => sum + t.fileSize);

  DownloadsState copyWith({
    Map<String, DownloadedTrack>? tracks,
    Map<String, double>? progress,
    int? queueLength,
    Set<String>? queuedTrackIds,
    Map<String, DownloadedPlaylist>? playlists,
    bool? isBlockedByWifiOnly,
  }) => DownloadsState(
    tracks: tracks ?? this.tracks,
    progress: progress ?? this.progress,
    queueLength: queueLength ?? this.queueLength,
    queuedTrackIds: queuedTrackIds ?? this.queuedTrackIds,
    playlists: playlists ?? this.playlists,
    isBlockedByWifiOnly: isBlockedByWifiOnly ?? this.isBlockedByWifiOnly,
  );
}

final downloadManagerProvider =
    NotifierProvider<DownloadManager, DownloadsState>(DownloadManager.new);

class DownloadManager extends Notifier<DownloadsState> {
  // No receiveTimeout — file downloads can take a while. connectTimeout still
  // applies so we fail fast when the server is unreachable.
  late final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 5)),
  );
  Directory? _dir;
  File? _manifestFile;
  File? _playlistsFile;
  CancelToken? _activeCancelToken;
  final List<Track> _queue = [];
  bool _running = false;

  @override
  DownloadsState build() {
    if (!kIsWeb) _bootstrap();
    return const DownloadsState();
  }

  bool get supported => !kIsWeb;
  bool get _appleCompatibilityMode =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _bootstrap() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/downloads');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;

      _manifestFile = File('${dir.path}/manifest.json');
      _playlistsFile = File('${dir.path}/playlists.json');

      Map<String, DownloadedTrack> tracks = {};
      if (_manifestFile!.existsSync()) {
        final raw = await _manifestFile!.readAsString();
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        tracks = {
          for (final json in list)
            json['id'] as String: DownloadedTrack.fromJson(json),
        };
      }

      Map<String, DownloadedPlaylist> playlists = {};
      if (_playlistsFile!.existsSync()) {
        final raw = await _playlistsFile!.readAsString();
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        playlists = {
          for (final json in list)
            json['id'] as String: DownloadedPlaylist.fromJson(json),
        };
      }

      state = state.copyWith(tracks: tracks, playlists: playlists);
    } catch (_) {}
  }

  String? _detectAudioExtension(File file) {
    try {
      final raf = file.openSync(mode: FileMode.read);
      final bytes = raf.readSync(32);
      raf.closeSync();
      if (bytes.length < 4) return null;
      bool startsWith(List<int> signature) {
        if (bytes.length < signature.length) return false;
        for (var i = 0; i < signature.length; i++) {
          if (bytes[i] != signature[i]) return false;
        }
        return true;
      }

      if (startsWith(const [0x49, 0x44, 0x33])) return 'mp3'; // ID3
      if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return 'mp3';
      if (startsWith(const [0x66, 0x4C, 0x61, 0x43])) return 'flac';
      if (startsWith(const [0x4F, 0x67, 0x67, 0x53])) return 'ogg';
      if (startsWith(const [0x52, 0x49, 0x46, 0x46])) return 'wav';
      if (startsWith(const [0x46, 0x4F, 0x52, 0x4D])) return 'aiff';
      if (bytes.length >= 12 &&
          bytes[4] == 0x66 &&
          bytes[5] == 0x74 &&
          bytes[6] == 0x79 &&
          bytes[7] == 0x70) {
        return 'm4a';
      }
    } catch (_) {}
    return null;
  }

  File _normalizeDownloadedPath(String trackId, File file) {
    final detected = _detectAudioExtension(file);
    if (detected == null) return file;
    final target = File('${file.parent.path}/$trackId.$detected');
    if (file.path == target.path) return file;
    try {
      if (target.existsSync()) target.deleteSync();
      file.renameSync(target.path);
      return target;
    } catch (_) {
      return file;
    }
  }

  Future<void> _persistTracks() async {
    final file = _manifestFile;
    if (file == null) return;
    await file.writeAsString(
      jsonEncode(state.tracks.values.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> _persistPlaylists() async {
    final file = _playlistsFile;
    if (file == null) return;
    await file.writeAsString(
      jsonEncode(state.playlists.values.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> enqueueTrack(Track track) async {
    if (!supported) return;
    if (state.isDownloaded(track.id)) return;
    if (!_queue.any((t) => t.id == track.id)) {
      _queue.add(track);
      state = state.copyWith(
        queueLength: _queue.length,
        queuedTrackIds: {...state.queuedTrackIds, track.id},
      );
    }
    if (!_running) unawaited(_drain());
  }

  Future<void> enqueueAlbum(Album album) async {
    for (final t in album.tracks) {
      await enqueueTrack(t);
    }
  }

  Future<void> enqueuePlaylist(PlaylistDetail playlist) async {
    await cachePlaylistMetadata(playlist);

    for (final t in playlist.tracks) {
      await enqueueTrack(t);
    }
  }

  /// Persists playlist metadata so it can be reconstructed while offline,
  /// including cases where songs were downloaded outside playlist downloads.
  Future<void> cachePlaylistMetadata(PlaylistDetail playlist) async {
    if (!supported) return;
    final trackIds = playlist.tracks.map((t) => t.id).toList(growable: false);
    final existing = state.playlists[playlist.id];
    if (existing != null &&
        existing.name == playlist.name &&
        existing.imageTag == playlist.imageTag &&
        listEquals(existing.trackIds, trackIds)) {
      return;
    }

    final updated = DownloadedPlaylist(
      id: playlist.id,
      name: playlist.name,
      imageTag: playlist.imageTag,
      trackIds: trackIds,
    );
    state = state.copyWith(
      playlists: {...state.playlists, playlist.id: updated},
    );
    await _persistPlaylists();
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final playlist = state.playlists[playlistId];
    if (playlist == null) return;
    state = state.copyWith(
      playlists: {
        ...state.playlists,
        playlistId: DownloadedPlaylist(
          id: playlist.id,
          name: name,
          imageTag: playlist.imageTag,
          trackIds: playlist.trackIds,
        ),
      },
    );
    await _persistPlaylists();
  }

  Future<void> reorderPlaylist(String playlistId, List<String> trackIds) async {
    final playlist = state.playlists[playlistId];
    if (playlist == null) return;
    state = state.copyWith(
      playlists: {
        ...state.playlists,
        playlistId: DownloadedPlaylist(
          id: playlist.id,
          name: playlist.name,
          imageTag: playlist.imageTag,
          trackIds: trackIds,
        ),
      },
    );
    await _persistPlaylists();
  }

  Future<void> deleteTracks(List<String> trackIds) async {
    for (final id in trackIds) {
      await deleteTrack(id);
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    final playlist = state.playlists[playlistId];
    if (playlist != null) {
      for (final id in playlist.trackIds) {
        await deleteTrack(id);
      }
    }
    final playlists = Map<String, DownloadedPlaylist>.from(state.playlists)
      ..remove(playlistId);
    state = state.copyWith(playlists: playlists);
    await _persistPlaylists();
  }

  Future<void> _drain() async {
    _running = true;
    if (state.isBlockedByWifiOnly) {
      state = state.copyWith(isBlockedByWifiOnly: false);
    }
    try {
      while (_queue.isNotEmpty) {
        final prefs = ref.read(downloadPreferencesProvider);
        if (prefs.wifiOnly) {
          final connectivity = await Connectivity().checkConnectivity();
          if (!connectivity.contains(ConnectivityResult.wifi)) {
            state = state.copyWith(isBlockedByWifiOnly: true);
            break;
          }
        }
        final track = _queue.removeAt(0);
        state = state.copyWith(
          queueLength: _queue.length,
          queuedTrackIds: {...state.queuedTrackIds}..remove(track.id),
        );
        await _downloadOne(track);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _downloadOne(Track track) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final url = repo.streamUrl(
      track.id,
      compatibilityMode: _appleCompatibilityMode,
    );
    final dir = _dir;
    if (dir == null) return;
    final preferredExt = _appleCompatibilityMode ? 'mp3' : 'audio';
    var dest = File('${dir.path}/${track.id}.$preferredExt');

    final progress = Map<String, double>.from(state.progress);
    progress[track.id] = 0;
    state = state.copyWith(progress: progress);

    final cancelToken = CancelToken();
    try {
      _activeCancelToken = cancelToken;
      await _dio.download(
        url,
        dest.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final next = Map<String, double>.from(state.progress);
          next[track.id] = received / total;
          state = state.copyWith(progress: next);
        },
      );
      dest = _normalizeDownloadedPath(track.id, dest);

      final size = dest.existsSync() ? dest.lengthSync() : 0;
      final artworkPath = await _cacheArtwork(track);
      final saved = DownloadedTrack(
        id: track.id,
        name: track.name,
        albumId: track.albumId,
        albumName: track.albumName,
        artistName: track.artistName,
        durationMs: track.duration.inMilliseconds,
        trackNumber: track.trackNumber,
        discNumber: track.discNumber,
        imageItemId: track.imageItemId,
        imageTag: track.imageTag,
        filePath: dest.path,
        fileSize: size,
        artworkPath: artworkPath,
        downloadedAt: DateTime.now(),
      );

      final tracks = Map<String, DownloadedTrack>.from(state.tracks);
      tracks[track.id] = saved;
      final clearedProgress = Map<String, double>.from(state.progress)
        ..remove(track.id);
      state = state.copyWith(tracks: tracks, progress: clearedProgress);
      await _persistTracks();
    } catch (_) {
      try {
        if (dest.existsSync()) dest.deleteSync();
      } catch (_) {}
      final clearedProgress = Map<String, double>.from(state.progress)
        ..remove(track.id);
      state = state.copyWith(progress: clearedProgress);
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }
  }

  Future<String?> _cacheArtwork(Track track) async {
    final dir = _dir;
    if (dir == null) return null;
    if (track.imageTag == null || track.imageTag!.isEmpty) return null;

    final imageItemId = track.albumImageItemId ?? track.albumId ?? track.id;
    final safeTag = track.imageTag!.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final cover = File('${dir.path}/art_${imageItemId}_$safeTag.jpg');
    if (cover.existsSync()) return cover.path;

    try {
      final repo = ref.read(jellyfinRepositoryProvider);
      final url = repo.imageUrl(
        imageItemId,
        imageTag: track.imageTag,
        size: 800,
      );
      await _dio.download(url, cover.path);
      if (cover.existsSync()) return cover.path;
    } catch (_) {
      try {
        if (cover.existsSync()) cover.deleteSync();
      } catch (_) {}
    }
    return null;
  }

  Future<void> deleteTrack(String trackId) async {
    final t = state.tracks[trackId];
    if (t == null) return;
    try {
      final f = File(t.filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    _queue.removeWhere((q) => q.id == trackId);
    final tracks = Map<String, DownloadedTrack>.from(state.tracks)
      ..remove(trackId);
    final queued = {...state.queuedTrackIds}..remove(trackId);
    state = state.copyWith(
      tracks: tracks,
      queueLength: _queue.length,
      queuedTrackIds: queued,
    );
    await _persistTracks();
  }

  Future<void> deleteAlbum(String albumId) async {
    final ids = state.tracks.values
        .where((t) => t.albumId == albumId)
        .map((t) => t.id)
        .toList();
    for (final id in ids) {
      await deleteTrack(id);
    }
  }

  String? localArtworkPath(String trackId) {
    final path = state.tracks[trackId]?.artworkPath;
    if (path == null) return null;
    try {
      final file = File(path);
      if (file.existsSync()) return file.path;
    } catch (_) {}
    return null;
  }

  Future<void> clearAllDownloads() async {
    _activeCancelToken?.cancel('User requested delete all downloads');
    _activeCancelToken = null;
    _queue.clear();

    final dir = _dir;
    if (dir != null && dir.existsSync()) {
      try {
        for (final entity in dir.listSync(recursive: false)) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    }

    state = state.copyWith(
      tracks: const {},
      progress: const {},
      queueLength: 0,
      queuedTrackIds: const {},
      playlists: const {},
      isBlockedByWifiOnly: false,
    );

    await _persistTracks();
    await _persistPlaylists();
  }

  String? localPath(String trackId) => state.tracks[trackId]?.filePath;
}
