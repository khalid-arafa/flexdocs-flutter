import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexdocs_flutter/src/api_client.dart';
import 'package:flexdocs_flutter/src/models/credentials.dart';
import 'package:flexdocs_flutter/src/models/api_client_options.dart';
import 'package:flexdocs_flutter/src/models/api_response.dart';

/// A mock HTTP adapter for Dio that returns preconfigured responses.
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

  void setError() {
    handler = null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (handler != null) {
      return handler!(options);
    }
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'Mock connection error',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Credentials creds;
  late Dio dio;
  late MockHttpAdapter mockAdapter;

  setUp(() {
    creds = Credentials(
      baseUrl: 'https://api.example.com',
      projectCode: 'test-project',
      projectToken: 'test-token-123',
    );
    dio = Dio();
    mockAdapter = MockHttpAdapter();
    dio.httpClientAdapter = mockAdapter;
  });

  group('ApiClient headers', () {
    test('adds project-token header to requests', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final client = ApiClient(credentials: creds, dio: dio);
      await client.get(url: '/test');

      expect(mockAdapter.requests, hasLength(1));
      expect(mockAdapter.requests.first.headers['project-token'], 'test-token-123');
    });

    test('adds Bearer token when getToken is provided', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final client = ApiClient(
        credentials: creds,
        options: ApiClientOptions(getToken: () async => 'user-jwt-token'),
        dio: dio,
      );
      await client.get(url: '/test');

      expect(
        mockAdapter.requests.first.headers['Authorization'],
        'Bearer user-jwt-token',
      );
    });

    test('does not add Authorization when getToken returns null', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final client = ApiClient(
        credentials: creds,
        options: ApiClientOptions(getToken: () async => null),
        dio: dio,
      );
      await client.get(url: '/test');

      expect(mockAdapter.requests.first.headers['Authorization'], isNull);
    });
  });

  group('ApiClient HTTP methods', () {
    late ApiClient client;

    setUp(() {
      mockAdapter.setResponse(statusCode: 200, data: {'result': 'ok'});
      client = ApiClient(credentials: creds, dio: dio);
    });

    test('GET request', () async {
      final response = await client.get(url: '/data');
      expect(response.ok, isTrue);
      expect(response.status, 200);
      expect(mockAdapter.requests.first.method, 'GET');
    });

    test('POST request with data', () async {
      final response = await client.post(url: '/data', data: {'name': 'test'});
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
    });

    test('PUT request with data', () async {
      final response = await client.put(url: '/data', data: {'name': 'updated'});
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'PUT');
    });

    test('DELETE request', () async {
      final response = await client.delete(url: '/data');
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'DELETE');
    });
  });

  group('ApiClient response normalization', () {
    test('200 response is ok', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'id': '123'});
      final client = ApiClient(credentials: creds, dio: dio);
      final response = await client.get(url: '/test');

      expect(response.ok, isTrue);
      expect(response.status, 200);
    });

    test('404 response is not ok', () async {
      mockAdapter.setResponse(statusCode: 404, data: {'error': 'Not found'});
      final client = ApiClient(credentials: creds, dio: dio);
      final response = await client.get(url: '/test');

      expect(response.ok, isFalse);
      expect(response.status, 404);
      expect(response.error, isNotNull);
    });

    test('500 response is not ok', () async {
      mockAdapter.setResponse(statusCode: 500, data: {'error': 'Server error'});
      final client = ApiClient(credentials: creds, dio: dio);
      final response = await client.get(url: '/test');

      expect(response.ok, isFalse);
      expect(response.status, 500);
    });
  });

  group('ApiClient retry logic', () {
    test('retries on connection error', () async {
      var callCount = 0;
      mockAdapter.handler = (options) {
        callCount++;
        if (callCount < 3) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'Connection failed',
          );
        }
        return ResponseBody.fromString(
          jsonEncode({'ok': true}),
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      };

      final client = ApiClient(
        credentials: creds,
        options: const ApiClientOptions(retryAttempts: 3, retryDelay: 1),
        dio: dio,
      );

      final response = await client.get(url: '/test');
      expect(response.ok, isTrue);
      expect(callCount, 3);
    });

    test('gives up after max retries', () async {
      mockAdapter.setError();

      final client = ApiClient(
        credentials: creds,
        options: const ApiClientOptions(retryAttempts: 2, retryDelay: 1),
        dio: dio,
      );

      final response = await client.get(url: '/test');
      expect(response.ok, isFalse);
      // Original + 2 retries = 3 total requests
      expect(mockAdapter.requests, hasLength(3));
    });

    test('calls onError callback on failure', () async {
      mockAdapter.setError();
      Object? capturedError;

      final client = ApiClient(
        credentials: creds,
        options: ApiClientOptions(
          retryAttempts: 0,
          onError: (e) => capturedError = e,
        ),
        dio: dio,
      );

      await client.get(url: '/test');
      expect(capturedError, isNotNull);
    });
  });

  group('ApiClient.test()', () {
    test('returns true on successful connection', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'connected': true});
      final client = ApiClient(credentials: creds, dio: dio);

      final result = await client.test();
      expect(result, isTrue);
      expect(mockAdapter.requests.first.path, contains('/projects/test-project/test-connection'));
    });

    test('returns false on failed connection', () async {
      mockAdapter.setError();
      final client = ApiClient(
        credentials: creds,
        options: const ApiClientOptions(retryAttempts: 0),
        dio: dio,
      );

      final result = await client.test();
      expect(result, isFalse);
    });
  });

  group('ApiResponse.fromDioResponse', () {
    test('extracts message from response data', () {
      final dioResponse = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 200,
        data: {'message': 'Success', 'id': '123'},
      );

      final apiResponse = ApiResponse.fromDioResponse(dioResponse);
      expect(apiResponse.ok, isTrue);
      expect(apiResponse.message, 'Success');
      expect(apiResponse.error, isNull);
    });

    test('extracts error from failed response', () {
      final dioResponse = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 400,
        data: {'error': 'Bad request'},
      );

      final apiResponse = ApiResponse.fromDioResponse(dioResponse);
      expect(apiResponse.ok, isFalse);
      expect(apiResponse.error, 'Bad request');
    });
  });
}
