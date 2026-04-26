import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final wikipediaRepositoryProvider = Provider<WikipediaRepository>(
  (ref) => WikipediaRepository(),
);

/// Returns the artist's Wikipedia thumbnail URL, or null.
/// Not autoDispose so images survive navigation and list scrolling.
final artistImageProvider = FutureProvider.family<String?, String>(
  (ref, artistName) =>
      ref.read(wikipediaRepositoryProvider).artistImageUrl(artistName),
);

/// Returns a short bio extract from Wikipedia, or null if unavailable.
final artistBioProvider = FutureProvider.family<String?, String>(
  (ref, artistName) =>
      ref.read(wikipediaRepositoryProvider).artistBio(artistName),
);

class WikipediaRepository {
  WikipediaRepository() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://en.wikipedia.org',
      headers: {'User-Agent': 'AltSound/1.0 (music-player-app)'},
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  late final Dio _dio;

  final _imageCache = <String, String?>{};
  final _bioCache = <String, String?>{};

  Future<String?> artistImageUrl(String artistName) async {
    if (_imageCache.containsKey(artistName)) return _imageCache[artistName];
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/w/api.php',
        queryParameters: {
          'action': 'query',
          'titles': artistName,
          'prop': 'pageimages',
          'pithumbsize': 200,
          'format': 'json',
          'redirects': 1,
        },
      );
      final pages = res.data?['query']?['pages'] as Map?;
      String? url;
      if (pages != null) {
        for (final page in pages.values) {
          url = (page as Map?)?['thumbnail']?['source'] as String?;
          break;
        }
      }
      _imageCache[artistName] = url;
      return url;
    } catch (_) {
      _imageCache[artistName] = null;
      return null;
    }
  }

  Future<String?> artistBio(String artistName) async {
    if (_bioCache.containsKey(artistName)) return _bioCache[artistName];
    try {
      final encoded = Uri.encodeComponent(artistName);
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/rest_v1/page/summary/$encoded',
      );
      final extract = res.data?['extract'] as String?;
      _bioCache[artistName] = extract;
      return extract;
    } catch (_) {
      _bioCache[artistName] = null;
      return null;
    }
  }
}
