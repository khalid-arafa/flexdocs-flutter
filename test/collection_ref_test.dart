import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/collection_ref.dart';
import 'package:flexdocs_flutter/src/api_client.dart';
import 'package:flexdocs_flutter/src/socket_service.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';
import 'package:flexdocs_flutter/src/models/query_options.dart';

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
  late CollectionRef col;

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
    col = CollectionRef(
      credentials: creds,
      colPath: 'users',
      apiClient: apiClient,
      socketService: socketService,
    );
  });

  group('CollectionRef URL', () {
    test('builds correct URL', () {
      expect(col.url, '/projects/myproject/db/users');
    });
  });

  group('CollectionRef query builder', () {
    test('where adds filter to query', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.where('age', WhereFilter(isGreaterThan: 18));
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['filter'], {'age': {'\$gt': 18}});
    });

    test('where with equality', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.where('status', WhereFilter(isEqualTo: 'active'));
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['filter'], {'status': 'active'});
    });

    test('whereRaw adds raw filter', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.whereRaw({
        '\$or': [
          {'role': 'admin'},
          {'isMod': true},
        ]
      });
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['filter']['\$or'], hasLength(2));
    });

    test('chaining multiple where calls', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col
          .where('age', WhereFilter(isGreaterThan: 18))
          .where('status', WhereFilter(isEqualTo: 'active'));
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['filter']['age'], {'\$gt': 18});
      expect(body['filter']['status'], 'active');
    });

    test('sort sets sort order', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.sort('name', SortDirection.ascending);
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['sort'], {'name': 1});
    });

    test('limit sets max results', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.limit(50);
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['limit'], 50);
    });

    test('skip sets offset', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.skip(10);
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['skip'], 10);
      expect(body.containsKey('page'), isFalse);
    });

    test('page sets page-based pagination', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.page(3, 25);
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['page'], 3);
      expect(body['ipp'], 25);
      expect(body.containsKey('limit'), isFalse);
    });

    test('skip nullifies page', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.page(3).skip(10);
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body.containsKey('page'), isFalse);
      expect(body['skip'], 10);
    });

    test('page throws on < 1', () {
      expect(() => col.page(0), throwsArgumentError);
    });

    test('select with list', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.select(['name', 'email']);
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['select'], {'name': 1, 'email': 1});
    });

    test('select with string', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.select('name email age');
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['select'], {'name': 1, 'email': 1, 'age': 1});
    });

    test('select with map', () async {
      mockAdapter.setResponse(statusCode: 200, data: []);

      col.select({'name': 1, 'email': 1});
      await col.get();

      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['select'], {'name': 1, 'email': 1});
    });
  });

  group('CollectionRef CRUD', () {
    test('get() returns list of documents', () async {
      mockAdapter.setResponse(statusCode: 200, data: [
        {'_id': '1', 'name': 'Alice'},
        {'_id': '2', 'name': 'Bob'},
      ]);

      final results = await col.get();
      expect(results, hasLength(2));
      expect(mockAdapter.requests.first.method, 'POST');
    });

    test('get() returns empty list on error', () async {
      mockAdapter.setResponse(statusCode: 500, data: {'error': 'fail'});

      final results = await col.get();
      expect(results, isEmpty);
    });

    test('add() posts to /add endpoint', () async {
      mockAdapter.setResponse(statusCode: 201, data: {'_id': 'new_1'});

      final response = await col.add({'name': 'Charlie'});
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
      expect(mockAdapter.requests.first.path, contains('/db/users/add'));
    });

    test('updateMany sends filter and newData', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'modifiedCount': 5});

      final response = await col.updateMany(
        filter: {'status': 'inactive'},
        newData: {'status': 'archived'},
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'PUT');
    });

    test('deleteMany sends filter', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'deletedCount': 3});

      final response = await col.deleteMany(filter: {'status': 'archived'});
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'DELETE');
    });

    test('getFilters calls GET /filters', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'fields': ['name', 'age']});

      final response = await col.getFilters();
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'GET');
      expect(mockAdapter.requests.first.path, contains('/db/users/filters'));
    });

    test('doc() returns a DocumentRef within the collection', () {
      final docRef = col.doc('user_1');
      expect(docRef.url, '/projects/myproject/db/users/user_1');
    });
  });
}
