import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/url_utils.dart';
import 'package:flexdocs_flutter/src/storage_service.dart';
import 'package:flexdocs_flutter/src/api_client.dart';
import 'package:flexdocs_flutter/src/socket_service.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';

void main() {
  group('url_utils encoding (F1/F2)', () {
    test('encodePathSegment percent-encodes traversal/injection chars', () {
      expect(encodePathSegment('a/b'), 'a%2Fb');
      expect(encodePathSegment('x?y#z'), 'x%3Fy%23z');
      expect(encodePathSegment('a b'), 'a%20b');
    });

    test('encodePathSegment rejects traversal segments', () {
      expect(() => encodePathSegment('..'), throwsArgumentError);
      expect(() => encodePathSegment('.'), throwsArgumentError);
    });

    test('encodePath preserves separators but encodes each segment', () {
      expect(encodePath('users/abc123'), 'users/abc123');
      expect(encodePath('col/with space'), 'col/with%20space');
      expect(() => encodePath('col/../secret'), throwsArgumentError);
    });

    test('buildQueryString encodes keys and values', () {
      expect(buildQueryString({}), '');
      expect(buildQueryString({'size': '200x200'}), '?size=200x200');
      // space → '+' (form-encoding), and '&' is escaped so it can't inject a param.
      expect(buildQueryString({'token': 'a b&c'}), '?token=a+b%26c');
    });
  });

  group('Credentials HTTPS requirement (F3)', () {
    test('allows https', () {
      expect(
        Credentials(baseUrl: 'https://api.example.com', projectCode: 'p', projectToken: 't').baseUrl,
        'https://api.example.com',
      );
    });

    test('allows http only for localhost/loopback', () {
      expect(
        Credentials(baseUrl: 'http://localhost:3000', projectCode: 'p', projectToken: 't').baseUrl,
        'http://localhost:3000',
      );
      expect(
        Credentials(baseUrl: 'http://127.0.0.1:8080', projectCode: 'p', projectToken: 't').baseUrl,
        'http://127.0.0.1:8080',
      );
    });

    test('rejects plaintext http for a non-loopback host', () {
      expect(
        () => Credentials(baseUrl: 'http://api.example.com', projectCode: 'p', projectToken: 't'),
        throwsArgumentError,
      );
    });
  });

  group('getFileUrl rejects traversal ids (F1)', () {
    test('throws on a traversal fileId', () {
      final creds = Credentials(
        baseUrl: 'https://api.example.com',
        projectCode: 'myproject',
        projectToken: 'token123',
      );
      final apiClient = ApiClient(credentials: creds, dio: Dio());
      final socketService = SocketService(credentials: creds);
      final storage = StorageService(
        credentials: creds,
        apiClient: apiClient,
        socketService: socketService,
      );
      expect(
        () => storage.getFileUrl(fileId: '..', filename: 'x.jpg'),
        throwsArgumentError,
      );
    });
  });
}
