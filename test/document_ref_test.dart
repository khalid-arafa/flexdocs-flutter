import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/document_ref.dart';
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
  });

  group('DocumentRef URL', () {
    test('builds correct URL', () {
      final doc = DocumentRef(
        credentials: creds,
        docPath: 'users/user_1',
        apiClient: apiClient,
        socketService: socketService,
      );
      expect(doc.url, '/projects/myproject/db/users/user_1');
    });

    test('normalizes leading/trailing slashes', () {
      final doc = DocumentRef(
        credentials: creds,
        docPath: '/users/user_1/',
        apiClient: apiClient,
        socketService: socketService,
      );
      expect(doc.url, '/projects/myproject/db/users/user_1');
    });
  });

  group('DocumentRef CRUD', () {
    late DocumentRef doc;

    setUp(() {
      doc = DocumentRef(
        credentials: creds,
        docPath: 'users/user_1',
        apiClient: apiClient,
        socketService: socketService,
      );
    });

    test('get() fetches document data', () async {
      mockAdapter.setResponse(
        statusCode: 200,
        data: {'_id': 'user_1', 'name': 'Alice'},
      );

      final result = await doc.get();
      expect(result, isNotNull);
      expect(result!['name'], 'Alice');
      expect(mockAdapter.requests.first.method, 'GET');
      expect(mockAdapter.requests.first.path,
          contains('/projects/myproject/db/users/user_1'));
    });

    test('get() returns null on failure', () async {
      mockAdapter.setResponse(statusCode: 404, data: {'error': 'Not found'});

      final result = await doc.get();
      expect(result, isNull);
    });

    test('update() sends PUT with update type', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await doc.update({'name': 'Bob'});
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'PUT');

      expect(mockAdapter.requests.first.method, 'PUT');
    });

    test('replace() sends PUT with replace type', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await doc.replace({'name': 'Charlie', 'age': 30});
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'PUT');
    });

    test('delete() sends DELETE request', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await doc.delete();
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'DELETE');
      expect(mockAdapter.requests.first.path,
          contains('/projects/myproject/db/users/user_1'));
    });
  });
}
