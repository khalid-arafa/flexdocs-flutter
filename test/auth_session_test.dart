/// Coverage for session lifetime (C12): refreshToken and revokeTokens.
///
/// The SDK had no knowledge of either endpoint. Its dartdoc even stated the
/// backend exposed no logout route, which stopped being true once tokenVersion
/// revocation shipped — so an app holding a long-lived token had no way to
/// extend a session or to end one on a device it no longer had.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/auth_service.dart';
import 'package:flexdocs_flutter/src/api_client.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';

class MockHttpAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  ResponseBody Function(RequestOptions)? handler;

  void setResponse({int statusCode = 200, dynamic data = const {}}) {
    handler = (_) => ResponseBody.fromString(
          jsonEncode(data),
          statusCode,
          headers: {
            'content-type': ['application/json'],
          },
        );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (handler != null) return handler!(options);
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late MockHttpAdapter mockAdapter;
  late AuthService auth;

  setUp(() {
    final creds = Credentials(
      baseUrl: 'https://api.example.com',
      projectCode: 'myproject',
      projectToken: 'token123',
    );
    final dio = Dio();
    mockAdapter = MockHttpAdapter();
    dio.httpClientAdapter = mockAdapter;
    auth = AuthService(
      credentials: creds,
      apiClient: ApiClient(credentials: creds, dio: dio),
    );
  });

  group('refreshToken', () {
    test('POSTs to the project-scoped refresh-token route', () async {
      mockAdapter.setResponse(data: {'token': 'fresh'});
      await auth.refreshToken();

      expect(mockAdapter.requests, hasLength(1));
      expect(mockAdapter.requests.first.method, 'POST');
      expect(
        mockAdapter.requests.first.path,
        '/projects/myproject/auth/refresh-token',
      );
    });

    test('returns the new token on success', () async {
      mockAdapter.setResponse(data: {'token': 'fresh-token-value'});
      expect(await auth.refreshToken(), 'fresh-token-value');
    });

    // A revoked or expired token is the ordinary case here, not an
    // exceptional one — the app's cue to send the user back to a login screen.
    test('returns null when the current token is no longer valid', () async {
      mockAdapter.setResponse(
        statusCode: 401,
        data: {'message': 'Invalid or expired token'},
      );
      expect(await auth.refreshToken(), isNull);
    });

    test('returns null rather than throwing when the network fails', () async {
      mockAdapter.handler = null; // adapter throws a connection error
      expect(await auth.refreshToken(), isNull);
    });

    test('returns null when the response carries no token field', () async {
      mockAdapter.setResponse(data: {'ok': true});
      expect(await auth.refreshToken(), isNull);
    });
  });

  group('revokeTokens', () {
    test('POSTs to the project-scoped revoke-tokens route', () async {
      mockAdapter.setResponse(data: {'success': true});
      await auth.revokeTokens();

      expect(mockAdapter.requests.first.method, 'POST');
      expect(
        mockAdapter.requests.first.path,
        '/projects/myproject/auth/revoke-tokens',
      );
    });

    test('reports success', () async {
      mockAdapter.setResponse(data: {'success': true});
      final response = await auth.revokeTokens();
      expect(response.ok, isTrue);
      expect(response.data['success'], isTrue);
    });

    test('surfaces a failure without throwing', () async {
      mockAdapter.setResponse(
        statusCode: 401,
        data: {'message': 'No token was provided'},
      );
      final response = await auth.revokeTokens();
      expect(response.ok, isFalse);
      expect(response.status, 401);
    });
  });
}
