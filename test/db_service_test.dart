import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/db_service.dart';
import 'package:flexdocs_flutter/src/api_client.dart';
import 'package:flexdocs_flutter/src/socket_service.dart';
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
  late Credentials creds;
  late Dio dio;
  late MockHttpAdapter mockAdapter;
  late ApiClient apiClient;
  late SocketService socketService;
  late DbService db;

  setUp(() {
    creds = Credentials(
      baseUrl: 'https://api.example.com',
      projectCode: 'myproject',
      projectToken: 'token123',
    );
    dio = Dio();
    mockAdapter = MockHttpAdapter();
    dio.httpClientAdapter = mockAdapter;
    apiClient = ApiClient(credentials: creds, dio: dio);
    socketService = SocketService(credentials: creds);
    db = DbService(
      credentials: creds,
      apiClient: apiClient,
      socketService: socketService,
    );
  });

  group('DbService', () {
    test('doc() returns DocumentRef with correct URL', () {
      final docRef = db.doc('users/user_1');
      expect(docRef.url, '/projects/myproject/db/users/user_1');
    });

    test('doc() throws on empty path', () {
      expect(() => db.doc(''), throwsArgumentError);
    });

    test('col() returns CollectionRef with correct URL', () {
      final colRef = db.col('users');
      expect(colRef.url, '/projects/myproject/db/users');
    });

    test('col() throws on empty path', () {
      expect(() => db.col(''), throwsArgumentError);
    });

    test('collections() calls POST /db/collections', () async {
      mockAdapter.setResponse(
        statusCode: 200,
        data: {'collections': ['users', 'posts']},
      );

      final response = await db.collections();
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
      expect(mockAdapter.requests.first.path, contains('/db/collections'));
    });

    test('createCollection() calls POST /db/collections/new', () async {
      mockAdapter.setResponse(statusCode: 201, data: {'name': 'orders'});

      final response = await db.createCollection(name: 'orders');
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
      expect(mockAdapter.requests.first.path, contains('/db/collections/new'));
    });

    test('renameCollection() calls PUT with correct URL', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await db.renameCollection(
        oldName: 'orders',
        newName: 'purchases',
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'PUT');
      expect(mockAdapter.requests.first.path,
          contains('/db/collections/orders/rename'));
    });
  });
}
