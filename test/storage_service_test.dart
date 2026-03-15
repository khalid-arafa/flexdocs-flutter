import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/storage_service.dart';
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
  late StorageService storage;

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
    storage = StorageService(
      credentials: creds,
      apiClient: apiClient,
      socketService: socketService,
    );
  });

  group('StorageService getFileUrl', () {
    test('builds basic URL', () {
      final url = storage.getFileUrl(fileId: 'f1', filename: 'photo.jpg');
      expect(url,
          'https://api.example.com/projects/myproject/storage/files/f1/photo.jpg');
    });

    test('includes size parameter', () {
      final url = storage.getFileUrl(
        fileId: 'f1',
        filename: 'photo.jpg',
        size: '200x200',
      );
      expect(url, contains('?size=200x200'));
    });

    test('includes token parameter', () {
      final url = storage.getFileUrl(
        fileId: 'f1',
        filename: 'photo.jpg',
        token: 'jwt123',
      );
      expect(url, contains('?token=jwt123'));
    });

    test('includes both size and token', () {
      final url = storage.getFileUrl(
        fileId: 'f1',
        filename: 'photo.jpg',
        size: '100x100',
        token: 'jwt123',
      );
      expect(url, contains('size=100x100'));
      expect(url, contains('token=jwt123'));
    });
  });

  group('StorageService file operations', () {
    test('deleteFile sends DELETE to /storage/files/:id', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await storage.deleteFile(fileId: 'file123');
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'DELETE');
      expect(mockAdapter.requests.first.path, contains('/storage/files/file123'));
    });
  });

  group('StorageService bucket operations', () {
    test('createBucket sends POST to /storage/buckets', () async {
      mockAdapter.setResponse(
          statusCode: 201, data: {'_id': 'b1', 'name': 'Photos'});

      final response = await storage.createBucket(
        name: 'Photos',
        description: 'Photo collection',
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
      expect(mockAdapter.requests.first.path, contains('/storage/buckets'));
    });

    test('createBucket with parentId', () async {
      mockAdapter.setResponse(statusCode: 201, data: {'_id': 'b2'});

      await storage.createBucket(name: 'Sub', parentId: 'b1');
      final body = mockAdapter.requests.first.data as Map<String, dynamic>;
      expect(body['parentId'], 'b1');
    });

    test('updateBucket sends PUT to /storage/buckets/:id', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await storage.updateBucket(
        bucketId: 'b1',
        name: 'Updated Name',
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'PUT');
      expect(mockAdapter.requests.first.path, contains('/storage/buckets/b1'));
    });

    test('deleteBucket sends DELETE to /storage/buckets/:id', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await storage.deleteBucket(bucketId: 'b1');
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'DELETE');
    });

    test('getBucketContent sends GET with query params', () async {
      mockAdapter.setResponse(
          statusCode: 200, data: {'files': [], 'buckets': []});

      final response = await storage.getBucketContent(
        bucketId: 'b1',
        page: 2,
        ipp: 10,
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'GET');
      expect(mockAdapter.requests.first.path,
          contains('/storage/buckets/b1/content'));
    });
  });

  group('StorageService search', () {
    test('search sends POST to /storage/search', () async {
      mockAdapter.setResponse(
          statusCode: 200, data: {'results': []});

      final response = await storage.search(
        searchTerm: 'photo',
        bucketId: 'b1',
        page: 1,
        ipp: 20,
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
      expect(mockAdapter.requests.first.path, contains('/storage/search'));
    });
  });
}
