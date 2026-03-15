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
  late Credentials creds;
  late Dio dio;
  late MockHttpAdapter mockAdapter;
  late ApiClient apiClient;
  late AuthService auth;

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
    auth = AuthService(credentials: creds, apiClient: apiClient);
  });

  group('AuthService validation', () {
    test('loginWithEmail throws on invalid email', () {
      expect(
        () => auth.loginWithEmail(email: 'invalid', password: 'password123'),
        throwsArgumentError,
      );
    });

    test('loginWithEmail throws on short password', () {
      expect(
        () => auth.loginWithEmail(email: 'test@example.com', password: '123'),
        throwsArgumentError,
      );
    });

    test('registerWithEmail throws on invalid email', () {
      expect(
        () => auth.registerWithEmail(email: 'bad', password: 'password123'),
        throwsArgumentError,
      );
    });

    test('changePassword throws when passwords are same', () {
      expect(
        () => auth.changePassword(
            oldPassword: 'password123', newPassword: 'password123'),
        throwsArgumentError,
      );
    });

    test('changePassword throws on short new password', () {
      expect(
        () => auth.changePassword(oldPassword: 'password123', newPassword: '12'),
        throwsArgumentError,
      );
    });

    test('loginWithToken throws on empty token', () {
      expect(
        () => auth.loginWithToken(token: ''),
        throwsArgumentError,
      );
    });

    test('sendResetPasswordEmail throws on invalid email', () {
      expect(
        () => auth.sendResetPasswordEmail(email: 'notanemail'),
        throwsArgumentError,
      );
    });
  });

  group('AuthService API calls', () {
    test('loginWithEmail sends POST to /auth/login', () async {
      mockAdapter.setResponse(
        statusCode: 200,
        data: {'token': 'jwt-token', 'user': {'email': 'test@example.com'}},
      );

      final response = await auth.loginWithEmail(
        email: 'test@example.com',
        password: 'password123',
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
      expect(mockAdapter.requests.first.path, contains('/auth/login'));
    });

    test('registerWithEmail sends POST to /auth/register', () async {
      mockAdapter.setResponse(statusCode: 201, data: {'token': 'jwt-token'});

      final response = await auth.registerWithEmail(
        email: 'new@example.com',
        password: 'password123',
        name: 'Test User',
        roles: ['user'],
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'POST');
      expect(mockAdapter.requests.first.path, contains('/auth/register'));
    });

    test('loginWithToken sends POST to /auth/token-login', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'token': 'new-jwt'});

      final response = await auth.loginWithToken(token: 'existing-jwt');
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.path, contains('/auth/token-login'));
    });

    test('anonymousLogin sends POST to /auth/anonymous', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'token': 'anon-jwt'});

      final response = await auth.anonymousLogin(name: 'Guest');
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.path, contains('/auth/anonymous'));
    });

    test('changePassword sends POST to /auth/change-password', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await auth.changePassword(
        oldPassword: 'oldpass123',
        newPassword: 'newpass456',
      );
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.path, contains('/auth/change-password'));
    });

    test('sendResetPasswordEmail sends POST to /auth/reset-password', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response =
          await auth.sendResetPasswordEmail(email: 'test@example.com');
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.path, contains('/auth/reset-password'));
    });

    test('sendEmailVerification sends GET to /auth/send-verification', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await auth.sendEmailVerification();
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.method, 'GET');
      expect(
          mockAdapter.requests.first.path, contains('/auth/send-verification'));
    });

    test('getCurrentUser returns user map on success', () async {
      mockAdapter.setResponse(
        statusCode: 200,
        data: {'_id': 'u1', 'email': 'test@example.com'},
      );

      final user = await auth.getCurrentUser();
      expect(user, isNotNull);
      expect(user!['email'], 'test@example.com');
      expect(mockAdapter.requests.first.path, contains('/auth/me'));
    });

    test('getCurrentUser returns null on failure', () async {
      mockAdapter.setResponse(statusCode: 401, data: {'error': 'Unauthorized'});

      final user = await auth.getCurrentUser();
      expect(user, isNull);
    });

    test('logout sends POST to /auth/logout', () async {
      mockAdapter.setResponse(statusCode: 200, data: {'ok': true});

      final response = await auth.logout();
      expect(response.ok, isTrue);
      expect(mockAdapter.requests.first.path, contains('/auth/logout'));
    });
  });
}
