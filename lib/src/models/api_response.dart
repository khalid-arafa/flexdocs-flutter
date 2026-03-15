import 'package:dio/dio.dart';

/// Normalized API response wrapper.
class ApiResponse {
  final bool ok;
  final int status;
  final dynamic data;
  final String? message;
  final String? error;

  const ApiResponse({
    required this.ok,
    required this.status,
    this.data,
    this.message,
    this.error,
  });

  factory ApiResponse.fromDioResponse(Response response) {
    final status = response.statusCode ?? 0;
    final ok = status >= 200 && status < 300;
    final responseData = response.data;

    String? message;
    String? error;
    if (responseData is Map) {
      message = responseData['message'] as String?;
      if (!ok) {
        error = responseData['error'] as String? ?? message;
      }
    }

    return ApiResponse(
      ok: ok,
      status: status,
      data: responseData,
      message: message,
      error: ok ? null : (error ?? 'Request failed with status $status'),
    );
  }

  factory ApiResponse.error({required String error, int status = 0}) {
    return ApiResponse(ok: false, status: status, error: error);
  }

  @override
  String toString() => 'ApiResponse(ok: $ok, status: $status)';
}
