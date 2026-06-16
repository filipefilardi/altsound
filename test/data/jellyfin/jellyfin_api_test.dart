import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:altsound/data/jellyfin/jellyfin_api.dart';
import 'package:altsound/data/jellyfin/models/jellyfin_session.dart';

void main() {
  group('JellyfinApi.publicServerInfo', () {
    test(
      'GETs public system info and returns normalized server details',
      () async {
        final adapter = _RecordingAdapter((options) async {
          expect(
            options.uri.toString(),
            'https://media.example.org/System/Info/Public',
          );
          expect(options.method, 'GET');
          final auth = options.headers['Authorization'] as String;
          expect(auth, contains('Client="AltSound"'));
          expect(auth, isNot(contains('Token=')));
          return _jsonResponse({
            'ServerName': 'Living Room',
            'Version': '10.10.7',
          });
        });
        final api = JellyfinApi(dio: Dio()..httpClientAdapter = adapter);

        final info = await api.publicServerInfo('media.example.org/');

        expect(info.serverUrl, 'https://media.example.org');
        expect(info.serverName, 'Living Room');
        expect(info.version, '10.10.7');
      },
    );
  });

  group('JellyfinApi.authenticate', () {
    test('POSTs credentials, parses the session, and binds auth', () async {
      final adapter = _RecordingAdapter((options) async {
        expect(
          options.uri.toString(),
          'https://media.example.org/Users/AuthenticateByName',
        );
        expect(options.method, 'POST');
        expect(options.data, {'Username': 'alice', 'Pw': 'hunter2'});
        final auth = options.headers['Authorization'] as String;
        expect(auth, contains('Client="AltSound"'));
        expect(auth, isNot(contains('Token=')));
        return _jsonResponse({
          'AccessToken': 'tok-1',
          'ServerId': 'server-1',
          'User': {'Id': 'user-1', 'Name': 'Alice'},
        });
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');

      final session = await api.authenticate(
        serverUrl: 'media.example.org/',
        username: 'alice',
        password: 'hunter2',
      );

      expect(session.serverUrl, 'https://media.example.org');
      expect(session.accessToken, 'tok-1');
      expect(session.userId, 'user-1');
      expect(session.serverId, 'server-1');
      expect(session.username, 'Alice');
      expect(dio.options.baseUrl, 'https://media.example.org');
      expect(dio.options.headers['Authorization'], contains('Token="tok-1"'));
    });
  });

  group('JellyfinApi.logout', () {
    test('clears local session even when server logout fails', () async {
      final adapter = _RecordingAdapter((_) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/Sessions/Logout'),
          type: DioExceptionType.connectionError,
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final api = JellyfinApi(dio: dio, deviceId: 'dev-1');
      api.bind(_session());

      await api.logout();

      expect(api.session, isNull);
      expect(dio.options.baseUrl, '');
      expect(dio.options.headers.containsKey('Authorization'), isFalse);
    });
  });
}

JellyfinSession _session({
  String serverUrl = 'https://x.example',
  String accessToken = 'tok',
}) => JellyfinSession(
  serverUrl: serverUrl,
  accessToken: accessToken,
  userId: 'u',
  serverId: 's',
  username: 'n',
);

ResponseBody _jsonResponse(Map<String, dynamic> body, {int status = 200}) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  return ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}
