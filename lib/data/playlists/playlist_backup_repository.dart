import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/search_normalization.dart';
import '../jellyfin/jellyfin_repository.dart';
import '../jellyfin/models/jellyfin_session.dart';
import '../jellyfin/models/media_item.dart';
import '../local/secure_storage.dart';

const _backupPrefsKey = 'playlist_backup_preferences_v1';
const _backupSchema = 'altsound.playlists.backup.v1';
const _autoBackupInterval = Duration(hours: 24);

final playlistBackupPreferencesProvider =
    NotifierProvider<PlaylistBackupPreferencesController, PlaylistBackupPrefs>(
      PlaylistBackupPreferencesController.new,
    );

final playlistBackupRepositoryProvider = Provider<PlaylistBackupRepository>(
  PlaylistBackupRepository.new,
);

final playlistBackupFilesProvider =
    FutureProvider.autoDispose<List<PlaylistBackupFile>>((ref) {
      return ref.watch(playlistBackupRepositoryProvider).listBackups();
    });

final playlistBackupDocumentProvider = FutureProvider.autoDispose
    .family<PlaylistBackupDocument, String>((ref, path) {
      return ref.watch(playlistBackupRepositoryProvider).readBackup(File(path));
    });

class PlaylistBackupPrefs {
  const PlaylistBackupPrefs({
    this.autoBackupEnabled = true,
    this.lastAutoBackupAt,
  });

  final bool autoBackupEnabled;
  final DateTime? lastAutoBackupAt;

  PlaylistBackupPrefs copyWith({
    bool? autoBackupEnabled,
    DateTime? lastAutoBackupAt,
  }) {
    return PlaylistBackupPrefs(
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      lastAutoBackupAt: lastAutoBackupAt ?? this.lastAutoBackupAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'autoBackupEnabled': autoBackupEnabled,
    'lastAutoBackupAt': lastAutoBackupAt?.toIso8601String(),
  };

  factory PlaylistBackupPrefs.fromJson(Map<String, dynamic> json) {
    final lastRaw = json['lastAutoBackupAt'] as String?;
    return PlaylistBackupPrefs(
      autoBackupEnabled: json['autoBackupEnabled'] as bool? ?? true,
      lastAutoBackupAt: lastRaw == null ? null : DateTime.tryParse(lastRaw),
    );
  }
}

class PlaylistBackupPreferencesController
    extends Notifier<PlaylistBackupPrefs> {
  @override
  PlaylistBackupPrefs build() {
    _restore();
    return const PlaylistBackupPrefs();
  }

  Future<void> _restore() async {
    final raw = await ref.read(secureStorageProvider).read(_backupPrefsKey);
    if (raw == null) return;
    try {
      state = PlaylistBackupPrefs.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {}
  }

  Future<void> _persist() async {
    await ref
        .read(secureStorageProvider)
        .write(_backupPrefsKey, jsonEncode(state.toJson()));
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    state = state.copyWith(autoBackupEnabled: enabled);
    await _persist();
  }

  Future<void> markAutoBackupCreated(DateTime at) async {
    state = state.copyWith(lastAutoBackupAt: at);
    await _persist();
  }
}

class PlaylistBackupRepository {
  PlaylistBackupRepository(this.ref);

  final Ref ref;

  Future<PlaylistBackupFile?> maybeCreateAutomaticBackup({
    JellyfinSession? session,
  }) async {
    final prefs = await _readPersistedPrefs();
    if (!prefs.autoBackupEnabled) return null;

    final last = prefs.lastAutoBackupAt;
    final now = DateTime.now();
    if (last != null && now.difference(last) < _autoBackupInterval) {
      return null;
    }

    final backup = await createBackup(session: session);
    await ref
        .read(playlistBackupPreferencesProvider.notifier)
        .markAutoBackupCreated(now);
    return backup;
  }

  Future<PlaylistBackupPrefs> _readPersistedPrefs() async {
    final raw = await ref.read(secureStorageProvider).read(_backupPrefsKey);
    if (raw == null) return ref.read(playlistBackupPreferencesProvider);
    try {
      return PlaylistBackupPrefs.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return ref.read(playlistBackupPreferencesProvider);
    }
  }

  Future<PlaylistBackupFile> createBackup({JellyfinSession? session}) async {
    final repo = ref.read(jellyfinRepositoryProvider);
    final playlists = await repo.playlists(limit: 500);
    final details = <PlaylistDetail>[];

    for (final playlist in playlists) {
      if (playlist.kind != MediaKind.playlist) continue;
      details.add(await repo.playlist(playlist.id));
    }

    final backup = PlaylistBackupDocument.fromPlaylists(
      playlists: details,
      session: session,
    );
    final file = await _backupFile(backup.createdAt);
    await file.parent.create(recursive: true);
    await file.writeAsString(_prettyJson(backup.toJson()));
    await _pruneOldBackups();
    return _describeBackupFile(file, backup);
  }

  Future<List<PlaylistBackupFile>> listBackups() async {
    final dir = await _backupsDirectory();
    if (!await dir.exists()) return const [];
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final backups = <PlaylistBackupFile>[];
    for (final file in files) {
      try {
        backups.add(await _describeBackupFile(file));
      } catch (_) {}
    }
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  Future<PlaylistBackupDocument> readBackup(File file) async {
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Backup file is not a JSON object.');
    }
    return PlaylistBackupDocument.fromJson(raw);
  }

  Future<PlaylistRestoreResult> restoreBackup(File file) async {
    final backup = await readBackup(file);
    final repo = ref.read(jellyfinRepositoryProvider);
    final current = await repo.playlists(limit: 500);
    final byName = <String, BrowseItem>{
      for (final playlist in current) _playlistNameKey(playlist.name): playlist,
    };

    var playlistsCreated = 0;
    var playlistsUpdated = 0;
    var tracksAdded = 0;
    var tracksSkipped = 0;
    var tracksMatchedByMetadata = 0;
    final unresolved = <PlaylistBackupTrack>[];

    for (final savedPlaylist in backup.playlists) {
      var target = byName[_playlistNameKey(savedPlaylist.name)];
      if (target == null) {
        target = await repo.createPlaylist(savedPlaylist.name);
        byName[_playlistNameKey(savedPlaylist.name)] = target;
        playlistsCreated++;
      }

      final existingDetail = await repo.playlist(target.id);
      final existingIds = existingDetail.tracks.map((t) => t.id).toSet();
      final targetWasEmpty = existingIds.isEmpty;
      var playlistChanged = false;

      for (final track in savedPlaylist.tracks) {
        final id = track.jellyfinTrackId;
        if (id != null &&
            id.isNotEmpty &&
            !targetWasEmpty &&
            existingIds.contains(id)) {
          tracksSkipped++;
          continue;
        }

        final result = await _restoreTrackToPlaylist(
          repo: repo,
          playlistId: target.id,
          track: track,
          existingIds: existingIds,
          skipExisting: !targetWasEmpty,
        );
        switch (result.status) {
          case _TrackRestoreStatus.added:
            playlistChanged = true;
            tracksAdded++;
            if (result.matchedByMetadata) tracksMatchedByMetadata++;
            if (_playlistNameKey(savedPlaylist.name) == 'liked songs') {
              await repo.setFavorite(result.trackId!, favorite: true);
            }
          case _TrackRestoreStatus.skipped:
            tracksSkipped++;
          case _TrackRestoreStatus.unresolved:
            unresolved.add(track);
        }
      }

      if (playlistChanged) {
        playlistsUpdated++;
      }
    }

    return PlaylistRestoreResult(
      playlistsCreated: playlistsCreated,
      playlistsUpdated: playlistsUpdated,
      tracksAdded: tracksAdded,
      tracksSkipped: tracksSkipped,
      tracksMatchedByMetadata: tracksMatchedByMetadata,
      unresolvedTracks: unresolved,
    );
  }

  Future<_TrackRestoreResult> _restoreTrackToPlaylist({
    required JellyfinRepository repo,
    required String playlistId,
    required PlaylistBackupTrack track,
    required Set<String> existingIds,
    required bool skipExisting,
  }) async {
    final savedId = track.jellyfinTrackId;
    if (savedId != null && savedId.isNotEmpty) {
      try {
        await repo.addTracksToPlaylist(
          trackIds: [savedId],
          playlistId: playlistId,
        );
        existingIds.add(savedId);
        return _TrackRestoreResult.added(
          trackId: savedId,
          matchedByMetadata: false,
        );
      } catch (_) {}
    }

    final resolvedId = await _resolveTrackIdByMetadata(repo, track);
    if (resolvedId == null || resolvedId.isEmpty) {
      return const _TrackRestoreResult.unresolved();
    }
    if (skipExisting && existingIds.contains(resolvedId)) {
      return const _TrackRestoreResult.skipped();
    }

    try {
      await repo.addTracksToPlaylist(
        trackIds: [resolvedId],
        playlistId: playlistId,
      );
      existingIds.add(resolvedId);
      return _TrackRestoreResult.added(
        trackId: resolvedId,
        matchedByMetadata: resolvedId != savedId,
      );
    } catch (_) {
      return const _TrackRestoreResult.unresolved();
    }
  }

  Future<String?> _resolveTrackIdByMetadata(
    JellyfinRepository repo,
    PlaylistBackupTrack track,
  ) async {
    final results = await repo.search(track.searchQuery);
    final candidates = results
        .where((item) => item.kind == MediaKind.track)
        .take(8)
        .toList();
    if (candidates.isEmpty) return null;

    BrowseItem? best;
    var bestScore = 0;
    for (final candidate in candidates) {
      final score = _backupTrackCandidateScore(track, candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return bestScore >= 70 ? best?.id : null;
  }

  Future<PlaylistBackupFile> importBackupFromPath(String path) async {
    final source = File(path.trim());
    if (!await source.exists()) {
      throw FileSystemException('Backup file does not exist.', source.path);
    }
    final backup = await readBackup(source);
    final dest = await _backupFile(backup.createdAt);
    await dest.parent.create(recursive: true);
    await source.copy(dest.path);
    return _describeBackupFile(dest, backup);
  }

  Future<PlaylistExportBundle> exportBackupBundle(File file) async {
    final backup = await readBackup(file);
    final dir = await _exportDirectory(backup.createdAt);
    await dir.create(recursive: true);

    final jsonFile = File('${dir.path}/altsound-playlists.json');
    final csvFile = File('${dir.path}/playlists.csv');
    await jsonFile.writeAsString(_prettyJson(backup.toJson()));
    await csvFile.writeAsString(_playlistCsv(backup));

    final m3uFiles = <File>[];
    for (final playlist in backup.playlists) {
      final fileName = '${_safeFileName(playlist.name)}.m3u8';
      final m3uFile = File('${dir.path}/$fileName');
      await m3uFile.writeAsString(_playlistM3u(playlist));
      m3uFiles.add(m3uFile);
    }

    return PlaylistExportBundle(
      directory: dir,
      jsonFile: jsonFile,
      csvFile: csvFile,
      m3uFiles: m3uFiles,
    );
  }

  Future<void> copyPathToClipboard(String path) {
    return Clipboard.setData(ClipboardData(text: path));
  }

  Future<Directory> _backupsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/playlist_backups');
  }

  Future<Directory> _exportsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/playlist_exports');
  }

  Future<File> _backupFile(DateTime createdAt) async {
    final dir = await _backupsDirectory();
    final stamp = _fileStamp(createdAt);
    return File('${dir.path}/altsound-playlists-$stamp.json');
  }

  Future<Directory> _exportDirectory(DateTime createdAt) async {
    final dir = await _exportsDirectory();
    return Directory('${dir.path}/altsound-playlists-${_fileStamp(createdAt)}');
  }

  Future<void> _pruneOldBackups() async {
    final backups = await listBackups();
    for (final old in backups.skip(20)) {
      try {
        await old.file.delete();
      } catch (_) {}
    }
  }

  Future<PlaylistBackupFile> _describeBackupFile(
    File file, [
    PlaylistBackupDocument? loaded,
  ]) async {
    final backup = loaded ?? await readBackup(file);
    final stat = await file.stat();
    return PlaylistBackupFile(
      file: file,
      createdAt: backup.createdAt,
      playlistCount: backup.playlists.length,
      trackCount: backup.playlists.fold(
        0,
        (sum, playlist) => sum + playlist.tracks.length,
      ),
      sizeBytes: stat.size,
    );
  }
}

class PlaylistBackupFile {
  const PlaylistBackupFile({
    required this.file,
    required this.createdAt,
    required this.playlistCount,
    required this.trackCount,
    required this.sizeBytes,
  });

  final File file;
  final DateTime createdAt;
  final int playlistCount;
  final int trackCount;
  final int sizeBytes;

  String get path => file.path;
}

class PlaylistExportBundle {
  const PlaylistExportBundle({
    required this.directory,
    required this.jsonFile,
    required this.csvFile,
    required this.m3uFiles,
  });

  final Directory directory;
  final File jsonFile;
  final File csvFile;
  final List<File> m3uFiles;
}

class PlaylistRestoreResult {
  const PlaylistRestoreResult({
    required this.playlistsCreated,
    required this.playlistsUpdated,
    required this.tracksAdded,
    required this.tracksSkipped,
    required this.tracksMatchedByMetadata,
    required this.unresolvedTracks,
  });

  final int playlistsCreated;
  final int playlistsUpdated;
  final int tracksAdded;
  final int tracksSkipped;
  final int tracksMatchedByMetadata;
  final List<PlaylistBackupTrack> unresolvedTracks;
}

enum _TrackRestoreStatus { added, skipped, unresolved }

class _TrackRestoreResult {
  const _TrackRestoreResult._({
    required this.status,
    this.trackId,
    this.matchedByMetadata = false,
  });

  const _TrackRestoreResult.added({
    required String trackId,
    required bool matchedByMetadata,
  }) : this._(
         status: _TrackRestoreStatus.added,
         trackId: trackId,
         matchedByMetadata: matchedByMetadata,
       );

  const _TrackRestoreResult.skipped()
    : this._(status: _TrackRestoreStatus.skipped);

  const _TrackRestoreResult.unresolved()
    : this._(status: _TrackRestoreStatus.unresolved);

  final _TrackRestoreStatus status;
  final String? trackId;
  final bool matchedByMetadata;
}

class PlaylistBackupDocument {
  const PlaylistBackupDocument({
    required this.schema,
    required this.createdAt,
    required this.source,
    required this.playlists,
  });

  final String schema;
  final DateTime createdAt;
  final PlaylistBackupSource source;
  final List<PlaylistBackupPlaylist> playlists;

  factory PlaylistBackupDocument.fromPlaylists({
    required List<PlaylistDetail> playlists,
    JellyfinSession? session,
  }) {
    final now = DateTime.now();
    return PlaylistBackupDocument(
      schema: _backupSchema,
      createdAt: now,
      source: PlaylistBackupSource.fromSession(session),
      playlists: [
        for (final playlist in playlists)
          PlaylistBackupPlaylist.fromPlaylist(playlist),
      ],
    );
  }

  factory PlaylistBackupDocument.fromJson(Map<String, dynamic> json) {
    final schema = json['schema'] as String?;
    if (schema != _backupSchema) {
      throw FormatException('Unsupported playlist backup schema: $schema');
    }
    final createdAtRaw = json['createdAt'] as String?;
    final createdAt = createdAtRaw == null
        ? null
        : DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException('Backup is missing a valid createdAt.');
    }
    return PlaylistBackupDocument(
      schema: schema!,
      createdAt: createdAt,
      source: PlaylistBackupSource.fromJson(
        (json['source'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      playlists: ((json['playlists'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (raw) =>
                PlaylistBackupPlaylist.fromJson(raw.cast<String, dynamic>()),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'createdAt': createdAt.toIso8601String(),
    'source': source.toJson(),
    'portableFormats': const [
      'altsound-json',
      'spotify-csv-ready',
      'youtube-music-csv-ready',
      'm3u8-metadata',
    ],
    'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
  };
}

class PlaylistBackupSource {
  const PlaylistBackupSource({
    required this.app,
    this.serverId,
    this.serverUrl,
    this.userId,
    this.username,
  });

  final String app;
  final String? serverId;
  final String? serverUrl;
  final String? userId;
  final String? username;

  factory PlaylistBackupSource.fromSession(JellyfinSession? session) {
    return PlaylistBackupSource(
      app: 'AltSound',
      serverId: session?.serverId,
      serverUrl: session?.serverUrl,
      userId: session?.userId,
      username: session?.username,
    );
  }

  factory PlaylistBackupSource.fromJson(Map<String, dynamic> json) {
    return PlaylistBackupSource(
      app: json['app'] as String? ?? 'AltSound',
      serverId: json['serverId'] as String?,
      serverUrl: json['serverUrl'] as String?,
      userId: json['userId'] as String?,
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'app': app,
    if (serverId != null) 'serverId': serverId,
    if (serverUrl != null) 'serverUrl': serverUrl,
    if (userId != null) 'userId': userId,
    if (username != null) 'username': username,
  };
}

class PlaylistBackupPlaylist {
  const PlaylistBackupPlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.durationMs,
    required this.tracks,
  });

  final String id;
  final String name;
  final int trackCount;
  final int durationMs;
  final List<PlaylistBackupTrack> tracks;

  factory PlaylistBackupPlaylist.fromPlaylist(PlaylistDetail playlist) {
    return PlaylistBackupPlaylist(
      id: playlist.id,
      name: playlist.name,
      trackCount: playlist.tracks.length,
      durationMs: playlist.totalDuration.inMilliseconds,
      tracks: [
        for (var index = 0; index < playlist.tracks.length; index++)
          PlaylistBackupTrack.fromTrack(
            playlist.tracks[index],
            position: index + 1,
          ),
      ],
    );
  }

  factory PlaylistBackupPlaylist.fromJson(Map<String, dynamic> json) {
    return PlaylistBackupPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Playlist',
      trackCount: json['trackCount'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      tracks: ((json['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (raw) => PlaylistBackupTrack.fromJson(raw.cast<String, dynamic>()),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trackCount': trackCount,
    'durationMs': durationMs,
    'tracks': tracks.map((track) => track.toJson()).toList(),
  };
}

class PlaylistBackupTrack {
  const PlaylistBackupTrack({
    required this.position,
    required this.title,
    required this.artists,
    this.album,
    this.durationMs,
    this.isrc,
    this.jellyfinTrackId,
    this.jellyfinAlbumId,
    this.jellyfinPlaylistItemId,
    this.trackNumber,
    this.discNumber,
  });

  final int position;
  final String title;
  final List<String> artists;
  final String? album;
  final int? durationMs;
  final String? isrc;
  final String? jellyfinTrackId;
  final String? jellyfinAlbumId;
  final String? jellyfinPlaylistItemId;
  final int? trackNumber;
  final int? discNumber;

  String get artistText => artists.join(', ');
  String get searchQuery {
    final parts = [
      title,
      if (artistText.isNotEmpty) artistText,
      if (album != null && album!.isNotEmpty) album!,
    ];
    return parts.join(' ');
  }

  factory PlaylistBackupTrack.fromTrack(Track track, {required int position}) {
    return PlaylistBackupTrack(
      position: position,
      title: track.name,
      artists: _splitArtists(track.artistName),
      album: track.albumName,
      durationMs: track.duration.inMilliseconds,
      jellyfinTrackId: track.id,
      jellyfinAlbumId: track.albumId,
      jellyfinPlaylistItemId: track.playlistItemId,
      trackNumber: track.trackNumber,
      discNumber: track.discNumber,
    );
  }

  factory PlaylistBackupTrack.fromJson(Map<String, dynamic> json) {
    final jellyfin = (json['jellyfin'] as Map?)?.cast<String, dynamic>();
    return PlaylistBackupTrack(
      position: json['position'] as int? ?? 0,
      title: json['title'] as String? ?? 'Untitled',
      artists: ((json['artists'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      album: json['album'] as String?,
      durationMs: json['durationMs'] as int?,
      isrc: json['isrc'] as String?,
      jellyfinTrackId:
          jellyfin?['trackId'] as String? ?? json['jellyfinTrackId'] as String?,
      jellyfinAlbumId:
          jellyfin?['albumId'] as String? ?? json['jellyfinAlbumId'] as String?,
      jellyfinPlaylistItemId:
          jellyfin?['playlistItemId'] as String? ??
          json['jellyfinPlaylistItemId'] as String?,
      trackNumber: json['trackNumber'] as int?,
      discNumber: json['discNumber'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'position': position,
    'title': title,
    'artists': artists,
    if (album != null) 'album': album,
    if (durationMs != null) 'durationMs': durationMs,
    if (isrc != null) 'isrc': isrc,
    if (trackNumber != null) 'trackNumber': trackNumber,
    if (discNumber != null) 'discNumber': discNumber,
    'searchQuery': searchQuery,
    'jellyfin': {
      if (jellyfinTrackId != null) 'trackId': jellyfinTrackId,
      if (jellyfinAlbumId != null) 'albumId': jellyfinAlbumId,
      if (jellyfinPlaylistItemId != null)
        'playlistItemId': jellyfinPlaylistItemId,
    },
  };
}

String _prettyJson(Object json) {
  return const JsonEncoder.withIndent('  ').convert(json);
}

String _playlistCsv(PlaylistBackupDocument backup) {
  final buffer = StringBuffer();
  buffer.writeln(
    [
      'playlist',
      'position',
      'title',
      'artists',
      'album',
      'duration_ms',
      'isrc',
      'jellyfin_track_id',
      'search_query',
    ].map(_csvCell).join(','),
  );
  for (final playlist in backup.playlists) {
    for (final track in playlist.tracks) {
      buffer.writeln(
        [
          playlist.name,
          track.position.toString(),
          track.title,
          track.artistText,
          track.album ?? '',
          track.durationMs?.toString() ?? '',
          track.isrc ?? '',
          track.jellyfinTrackId ?? '',
          track.searchQuery,
        ].map(_csvCell).join(','),
      );
    }
  }
  return buffer.toString();
}

String _playlistM3u(PlaylistBackupPlaylist playlist) {
  final buffer = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#PLAYLIST:${playlist.name}');
  for (final track in playlist.tracks) {
    final seconds = track.durationMs == null
        ? -1
        : (track.durationMs! / 1000).round();
    final label = [
      if (track.artistText.isNotEmpty) track.artistText,
      track.title,
    ].join(' - ');
    buffer
      ..writeln('#EXTINF:$seconds,$label')
      ..writeln('#EXTART:${track.artistText}')
      ..writeln('#EXTALB:${track.album ?? ''}')
      ..writeln(track.searchQuery);
  }
  return buffer.toString();
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

int _backupTrackCandidateScore(
  PlaylistBackupTrack backup,
  BrowseItem candidate,
) {
  var score = 0;
  final backupTitle = normalizeForSearch(backup.title);
  final candidateTitle = normalizeForSearch(candidate.name);
  final backupArtist = normalizeForSearch(backup.artistText);
  final candidateArtist = normalizeForSearch(candidate.subtitle ?? '');

  if (backupTitle.isNotEmpty && backupTitle == candidateTitle) {
    score += 55;
  } else if (searchMatches(backup.title, [candidate.name])) {
    score += 35;
  }

  if (backupArtist.isNotEmpty && candidateArtist.isNotEmpty) {
    if (backupArtist == candidateArtist ||
        backupArtist.contains(candidateArtist) ||
        candidateArtist.contains(backupArtist)) {
      score += 30;
    } else if (searchMatches(backup.artistText, [candidate.subtitle])) {
      score += 18;
    }
  }

  final durationMs = backup.durationMs;
  final candidateDuration = candidate.runTime;
  if (durationMs != null && candidateDuration != null) {
    final delta = (candidateDuration.inMilliseconds - durationMs).abs();
    if (delta <= 2000) {
      score += 20;
    } else if (delta <= 7000) {
      score += 10;
    }
  }

  return score;
}

List<String> _splitArtists(String artistName) {
  return artistName
      .split(RegExp(r'\s*,\s*'))
      .map((artist) => artist.trim())
      .where((artist) => artist.isNotEmpty)
      .toList();
}

String _playlistNameKey(String value) {
  return value.trim().toLowerCase();
}

String _fileStamp(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
}

String _safeFileName(String value) {
  final cleaned = value
      .trim()
      .replaceAll(RegExp(r'[^\w\s.-]+'), '')
      .replaceAll(RegExp(r'\s+'), '-');
  return cleaned.isEmpty ? 'playlist' : cleaned;
}
