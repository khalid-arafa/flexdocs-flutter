import 'package:dio/dio.dart';

import 'flexdocs_exception.dart';

/// Normalized API response wrapper.
class ApiResponse {
  final bool ok;
  final int status;
  final dynamic data;
  final String? message;
  final String? error;

  /// Stable machine-readable error identifier from the server, e.g.
  /// `NOT_FOUND`, `UNAUTHORIZED`, `FORBIDDEN`.
  ///
  /// The API attaches this to every error body alongside `message`, so callers
  /// can branch on a value that is safe to depend on instead of matching on
  /// message text that may be reworded at any time. Null on success, and null
  /// against an API build old enough to predate typed error responses — which
  /// is why [FlexDocsException.fromResponse] falls back to the status code.
  final String? code;

  const ApiResponse({
    required this.ok,
    required this.status,
    this.data,
    this.message,
    this.error,
    this.code,
  });

  factory ApiResponse.fromDioResponse(Response response) {
    final status = response.statusCode ?? 0;
    final ok = status >= 200 && status < 300;
    final responseData = response.data;

    String? message;
    String? error;
    String? code;
    if (responseData is Map) {
      message = responseData['message'] as String?;
      if (!ok) {
        error = responseData['error'] as String? ?? message;
        code = responseData['code'] as String?;
      }
    }

    return ApiResponse(
      ok: ok,
      status: status,
      data: responseData,
      message: message,
      error: ok ? null : (error ?? 'Request failed with status $status'),
      code: code,
    );
  }

  factory ApiResponse.error({
    required String error,
    int status = 0,
    String? code,
  }) {
    return ApiResponse(ok: false, status: status, error: error, code: code);
  }

  /// The typed exception this response represents, or null when it succeeded.
  FlexDocsException? get exception =>
      ok ? null : FlexDocsException.fromResponse(this);

  /// Returns [data] on success, throws the matching [FlexDocsException]
  /// otherwise.
  ///
  /// The SDK never throws these on your behalf — every call still hands back
  /// an [ApiResponse] so that checking `ok` stays a valid style. This is the
  /// opt-in for callers who would rather use try/catch, and the only way to
  /// tell a legitimately empty result from a denied one.
  dynamic orThrow() {
    final failure = exception;
    if (failure != null) throw failure;
    return data;
  }

  @override
  String toString() => 'ApiResponse(ok: $ok, status: $status)';
}
