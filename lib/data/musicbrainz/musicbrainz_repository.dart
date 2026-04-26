import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MusicBrainzArtist {
  const MusicBrainzArtist({
    required this.id,
    required this.name,
    this.disambiguation,
    this.country,
    this.type,
  });

  final String id;
  final String name;
  final String? disambiguation;
  final String? country;
  final String? type;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicBrainzArtist && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  factory MusicBrainzArtist.fromJson(Map<String, dynamic> json) {
    return MusicBrainzArtist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Artist',
      disambiguation: json['disambiguation'] as String?,
      country: json['country'] as String?,
      type: json['type'] as String?,
    );
  }
}

class MusicBrainzReleaseGroup {
  const MusicBrainzReleaseGroup({
    required this.id,
    required this.title,
    this.primaryType,
    this.firstReleaseDate,
    this.secondaryTypes = const [],
    this.artistName,
    this.artistId,
  });

  final String id;
  final String title;
  final String? primaryType;
  final String? firstReleaseDate;
  final List<String> secondaryTypes;
  final String? artistName;
  final String? artistId;

  String get coverArtUrl => 'https://coverartarchive.org/release-group/$id/front';

  String get year {
    final d = firstReleaseDate;
    if (d == null || d.isEmpty) return '';
    return d.split('-').first;
  }

  factory MusicBrainzReleaseGroup.fromJson(Map<String, dynamic> json) {
    final credits = json['artist-credit'] as List?;
    String? artistName;
    String? artistId;
    if (credits != null && credits.isNotEmpty) {
      final first = credits.first as Map?;
      final artist = first?['artist'] as Map?;
      artistName = artist?['name'] as String? ?? first?['name'] as String?;
      artistId = artist?['id'] as String?;
    }
    return MusicBrainzReleaseGroup(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      primaryType: json['primary-type'] as String?,
      firstReleaseDate: json['first-release-date'] as String?,
      secondaryTypes: (json['secondary-types'] as List?)?.cast<String>() ?? const [],
      artistName: artistName,
      artistId: artistId,
    );
  }
}

class MusicBrainzTrack {
  const MusicBrainzTrack({
    required this.number,
    required this.title,
    this.durationMs,
    this.discNumber = 1,
  });

  final String number;
  final String title;
  final int? durationMs;
  final int discNumber;

  String get formattedDuration {
    final ms = durationMs;
    if (ms == null || ms == 0) return '';
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

final musicBrainzRepositoryProvider = Provider<MusicBrainzRepository>(
  (ref) => MusicBrainzRepository(),
);

class MusicBrainzRepository {
  MusicBrainzRepository() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://musicbrainz.org/ws/2',
      headers: {
        'User-Agent': 'AltSound/1.0 (music-player-app)',
        'Accept': 'application/json',
      },
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  late final Dio _dio;

  // Respect MusicBrainz's 1 request/second guideline.
  DateTime _lastRequest = DateTime(2000);

    // Session-scoped caches. MusicBrainz data is stable; no TTL needed.
  final _releaseGroupCache = <String, List<MusicBrainzReleaseGroup>>{};
  final _artistSearchCache = <String, List<MusicBrainzArtist>>{};
  final _releaseSearchCache = <String, List<MusicBrainzReleaseGroup>>{};
  final _trackCache = <String, List<MusicBrainzTrack>>{};

  Future<void> _rateLimit() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequest);
    if (elapsed < const Duration(milliseconds: 1100)) {
      await Future.delayed(const Duration(milliseconds: 1100) - elapsed);
    }
    _lastRequest = DateTime.now();
  }

  Future<List<MusicBrainzArtist>> searchArtists(String term) async {
    if (term.trim().isEmpty) return const [];
    final key = term.trim().toLowerCase();
    if (_artistSearchCache.containsKey(key)) return _artistSearchCache[key]!;
    await _rateLimit();
    final res = await _dio.get<Map<String, dynamic>>(
      '/artist',
      queryParameters: {'query': term.trim(), 'limit': 10, 'fmt': 'json'},
    );
    final results = (res.data?['artists'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MusicBrainzArtist.fromJson)
        .toList();
    _artistSearchCache[key] = results;
    return results;
  }

  Future<List<MusicBrainzReleaseGroup>> searchReleaseGroups(String term) async {
    if (term.trim().isEmpty) return const [];
    final key = term.trim().toLowerCase();
    if (_releaseSearchCache.containsKey(key)) return _releaseSearchCache[key]!;
    await _rateLimit();
    final res = await _dio.get<Map<String, dynamic>>(
      '/release-group',
      queryParameters: {'query': term.trim(), 'limit': 10, 'fmt': 'json'},
    );
    final results = (res.data?['release-groups'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MusicBrainzReleaseGroup.fromJson)
        .toList();
    _releaseSearchCache[key] = results;
    return results;
  }

  Future<List<MusicBrainzReleaseGroup>> artistReleaseGroups(String artistMbid) async {
    if (artistMbid.isEmpty) return const [];
    if (_releaseGroupCache.containsKey(artistMbid)) return _releaseGroupCache[artistMbid]!;
    await _rateLimit();
    final res = await _dio.get<Map<String, dynamic>>(
      '/release-group',
      queryParameters: {
        'artist': artistMbid,
        'inc': 'artist-credits',
        'limit': 100,
        'fmt': 'json',
      },
    );
    final groups = (res.data?['release-groups'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MusicBrainzReleaseGroup.fromJson)
        .toList();
    groups.sort((a, b) {
      final aDate = a.firstReleaseDate ?? '';
      final bDate = b.firstReleaseDate ?? '';
      return bDate.compareTo(aDate);
    });
    _releaseGroupCache[artistMbid] = groups;
    return groups;
  }

  /// Returns the track listing for a release group by fetching its first
  /// official release. Returns [] if no releases or tracks are found.
  Future<List<MusicBrainzTrack>> releaseGroupTracks(String releaseGroupMbid) async {
    if (releaseGroupMbid.isEmpty) return const [];
    if (_trackCache.containsKey(releaseGroupMbid)) return _trackCache[releaseGroupMbid]!;
    await _rateLimit();
    final res = await _dio.get<Map<String, dynamic>>(
      '/release',
      queryParameters: {
        'release-group': releaseGroupMbid,
        'inc': 'recordings',
        'status': 'official',
        'limit': 1,
        'fmt': 'json',
      },
    );
    final releases = res.data?['releases'] as List? ?? const [];
    if (releases.isEmpty) {
      _trackCache[releaseGroupMbid] = const [];
      return const [];
    }
    final release = (releases.first as Map).map((k, v) => MapEntry('$k', v));
    final media = release['media'] as List? ?? const [];
    final tracks = <MusicBrainzTrack>[];
    for (var d = 0; d < media.length; d++) {
      final disc = (media[d] as Map).map((k, v) => MapEntry('$k', v));
      for (final t in (disc['tracks'] as List? ?? const []).whereType<Map>()) {
        final track = t.map((k, v) => MapEntry('$k', v));
        tracks.add(MusicBrainzTrack(
          number: track['number'] as String? ?? '${tracks.length + 1}',
          title: track['title'] as String? ??
              ((track['recording'] as Map?)?['title'] as String?) ??
              'Unknown',
          durationMs: track['length'] as int?,
          discNumber: d + 1,
        ));
      }
    }
    _trackCache[releaseGroupMbid] = tracks;
    return tracks;
  }
}
