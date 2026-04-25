import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../jellyfin/jellyfin_repository.dart';
import '../jellyfin/models/media_item.dart';
import 'downloaded_track.dart';

class DownloadProgress {
  const DownloadProgress({
    required this.trackId,
    required this.progress,
  });
  final String trackId;
  final double progress;
}

class DownloadsState {
  const DownloadsState({
    this.tracks = const {},
    this.progress = const {},
    this.queueLength = 0,
  });

  final Map<String, DownloadedTrack> tracks;
  final Map<String, double> progress;
  final int queueLength;

  bool isDownloaded(String trackId) => tracks.containsKey(trackId);
  double? progressFor(String trackId) => progress[trackId];

  int get totalSizeBytes =>
      tracks.values.fold(0, (sum, t) => sum + t.fileSize);

  DownloadsState copyWith({
    Map<String, DownloadedTrack>? tracks,
    Map<String, double>? progress,
    int? queueLength,
  }) =>
      DownloadsState(
        tracks: tracks ?? this.tracks,
        progress: progress ?? this.progress,
        queueLength: queueLength ?? this.queueLength,
      );
}

final downloadManagerProvider =
    NotifierProvider<DownloadManager, DownloadsState>(DownloadManager.new);

class DownloadManager extends Notifier<DownloadsState> {
  late final Dio _dio = Dio();
  Directory? _dir;
  File? _manifestFile;
  final List<Track> _queue = [];
  bool _running = false;

  @override
  DownloadsState build() {
    if (!kIsWeb) {
      // Fire-and-forget bootstrap from disk.
      _bootstrap();
    }
    return const DownloadsState();
  }

  bool get supported => !kIsWeb;

  Future<void> _bootstrap() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/downloads');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      _manifestFile = File('${dir.path}/manifest.json');
      if (_manifestFile!.existsSync()) {
        final raw = await _manifestFile!.readAsString();
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final map = {
          for (final json in list)
            json['id'] as String: DownloadedTrack.fromJson(json),
        };
        state = state.copyWith(tracks: map);
      }
    } catch (_) {
      // ignore — start with empty state
    }
  }

  Future<void> _persist() async {
    final file = _manifestFile;
    if (file == null) return;
    final list = state.tracks.values.map((t) => t.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }

  Future<void> enqueueTrack(Track track) async {
    if (!supported) return;
    if (state.isDownloaded(track.id)) return;
    if (_queue.any((t) => t.id == track.id)) return;
    _queue.add(track);
    state = state.copyWith(queueLength: _queue.length);
    if (!_running) unawaited(_drain());
  }

  Future<void> enqueueAlbum(Album album) async {
    for (final t in album.tracks) {
      await enqueueTrack(t);
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final track = _queue.removeAt(0);
        state = state.copyWith(queueLength: _queue.length);
        await _downloadOne(track);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _downloadOne(Track track) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final url = repo.streamUrl(track.id);
    final dir = _dir;
    if (dir == null) return;
    final dest = File('${dir.path}/${track.id}.audio');

    final progress = Map<String, double>.from(state.progress);
    progress[track.id] = 0;
    state = state.copyWith(progress: progress);

    try {
      await _dio.download(
        url,
        dest.path,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final next = Map<String, double>.from(state.progress);
          next[track.id] = received / total;
          state = state.copyWith(progress: next);
        },
      );

      final size = dest.existsSync() ? dest.lengthSync() : 0;
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
        downloadedAt: DateTime.now(),
      );

      final tracks = Map<String, DownloadedTrack>.from(state.tracks);
      tracks[track.id] = saved;
      final clearedProgress = Map<String, double>.from(state.progress)
        ..remove(track.id);
      state = state.copyWith(tracks: tracks, progress: clearedProgress);
      await _persist();
    } catch (_) {
      // remove the partial file and progress on failure
      try {
        if (dest.existsSync()) dest.deleteSync();
      } catch (_) {}
      final clearedProgress = Map<String, double>.from(state.progress)
        ..remove(track.id);
      state = state.copyWith(progress: clearedProgress);
    }
  }

  Future<void> deleteTrack(String trackId) async {
    final t = state.tracks[trackId];
    if (t == null) return;
    try {
      final f = File(t.filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    final tracks = Map<String, DownloadedTrack>.from(state.tracks)
      ..remove(trackId);
    state = state.copyWith(tracks: tracks);
    await _persist();
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

  String? localPath(String trackId) => state.tracks[trackId]?.filePath;
}
