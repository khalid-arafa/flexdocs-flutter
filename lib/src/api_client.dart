import 'package:dio/dio.dart';

import 'models/credentials.dart';
import 'models/api_client_options.dart';
import 'models/api_response.dart';
import 'logger.dart';

/// HTTP client wrapping Dio with auth headers, retry logic, and response normalization.
class ApiClient {
  final Credentials _credentials;
  final ApiClientOptions _options;
  late final Dio _dio;

  ApiClient({
    required Credentials credentials,
    ApiClientOptions options = const ApiClientOptions(),
    Dio? dio,
  })  : _credentials = credentials,
        _options = options {
    _dio = dio ?? Dio();
    _init();
  }

  void _init() {
    _dio.options
      ..baseUrl = _credentials.baseUrl
      ..connectTimeout = Duration(milliseconds: _options.timeout)
      ..receiveTimeout = Duration(milliseconds: _options.timeout)
      ..validateStatus = (_) => true;

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.headers['project-token'] = _credentials.projectToken;

        if (_options.getToken != null) {
          final token = await _options.getToken!();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }

        handler.next(options);
      },
      onError: (error, handler) {
        _options.onError?.call(error);
        handler.next(error);
      },
    ));
  }

  /// Base URL for project API requests.
  String get _projectUrl => '/projects/${_credentials.projectCode}';

  /// GET request.
  Future<ApiResponse> get({
    required String url,
    Map<String, dynamic>? queryParameters,
  }) {
    return _handleRequest('GET', url, queryParameters: queryParameters);
  }

  /// POST request.
  Future<ApiResponse> post({
    required String url,
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _handleRequest('POST', url, data: data, queryParameters: queryParameters);
  }

  /// PUT request.
  Future<ApiResponse> put({
    required String url,
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _handleRequest('PUT', url, data: data, queryParameters: queryParameters);
  }

  /// DELETE request.
  Future<ApiResponse> delete({
    required String url,
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _handleRequest('DELETE', url, data: data, queryParameters: queryParameters);
  }

  /// Test the connection to the server.
  Future<bool> test() async {
    try {
      final response = await get(url: '$_projectUrl/test-connection');
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  /// Handles a request with retry logic.
  Future<ApiResponse> _handleRequest(
    String method,
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    int retryCount = 0,
  }) async {
    try {
      final response = await _dio.request(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method),
      );

      final apiResponse = ApiResponse.fromDioResponse(response);

      if (!apiResponse.ok) {
        logger.warn('$method $url returned ${apiResponse.status}');
      }

      return apiResponse;
    } on DioException catch (e) {
      if (_shouldRetry(e) && retryCount < _options.retryAttempts) {
        final delay = _options.retryDelay * (1 << retryCount);
        logger.info('Retrying $method $url (attempt ${retryCount + 1}) in ${delay}ms');
        await Future.delayed(Duration(milliseconds: delay));
        return _handleRequest(
          method,
          url,
          data: data,
          queryParameters: queryParameters,
          retryCount: retryCount + 1,
        );
      }

      logger.error('$method $url failed: ${e.message}');
      _options.onError?.call(e);

      return ApiResponse.error(
        error: e.message ?? 'Request failed',
        status: e.response?.statusCode ?? 0,
      );
    } catch (e) {
      logger.error('$method $url unexpected error: $e');
      _options.onError?.call(e);
      return ApiResponse.error(error: e.toString());
    }
  }

  bool _shouldRetry(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }
    final statusCode = error.response?.statusCode ?? 0;
    return statusCode >= 500;
  }
}
