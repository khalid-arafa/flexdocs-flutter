import 'api_response.dart';

/// Base class for every error this SDK raises.
///
/// Before these existed, a failure surfaced three different ways depending on
/// where it happened — an [ArgumentError] from a validator, a bare
/// `Exception(String)` from an upload, or a non-throwing [ApiResponse] with
/// `ok: false` from anything that talked to the server. None of them carried a
/// status or a machine-readable code, so a caller wanting to tell "wrong
/// password" from "server is down" had no option but to match on message text.
///
/// The server now returns a stable `code` alongside `message` on every error
/// response, and [FlexDocsException.fromResponse] reads it. Catch the subtype
/// you care about:
///
/// ```dart
/// try {
///   final user = (await auth.loginWithEmail(email: e, password: p)).orThrow();
/// } on FlexDocsAuthException {
///   // bad credentials, or a revoked/expired token
/// } on FlexDocsNetworkException {
///   // never reached the server — worth retrying
/// } on FlexDocsException catch (e) {
///   showError(e.message);
/// }
/// ```
class FlexDocsException implements Exception {
  /// Human-readable description, taken from the server's `message` when there
  /// is one. Safe to show a user; not safe to branch on — use [code].
  final String message;

  /// Stable machine-readable identifier from the server, e.g. `NOT_FOUND`,
  /// `UNAUTHORIZED`. Null when the failure never reached the server, or came
  /// from an older API build that predates typed error responses.
  final String? code;

  /// HTTP status, or null for failures that produced no response at all.
  final int? status;

  /// The underlying error, when this wraps one.
  final Object? cause;

  const FlexDocsException(
    this.message, {
    this.code,
    this.status,
    this.cause,
  });

  /// Builds the most specific subtype the response justifies.
  ///
  /// A response that never reached the server (status 0) is a
  /// [FlexDocsNetworkException] regardless of its message, because that is the
  /// one distinction the old string-matching could never make reliably and the
  /// one most worth retrying.
  factory FlexDocsException.fromResponse(ApiResponse response) {
    final status = response.status;
    final message = response.error ?? response.message ?? 'Request failed';
    final code = response.code;

    if (status == 0) {
      return FlexDocsNetworkException(message, code: code, status: status);
    }
    switch (status) {
      case 400:
      case 422:
        return FlexDocsValidationException(message, code: code, status: status);
      case 401:
        return FlexDocsAuthException(message, code: code, status: status);
      case 403:
        return FlexDocsPermissionException(message, code: code, status: status);
      case 404:
        return FlexDocsNotFoundException(message, code: code, status: status);
      case 429:
        return FlexDocsRateLimitException(message, code: code, status: status);
    }
    if (status >= 500) {
      return FlexDocsServerException(message, code: code, status: status);
    }
    return FlexDocsException(message, code: code, status: status);
  }

  @override
  String toString() {
    final parts = <String>[
      ?code,
      if (status != null && status != 0) 'HTTP $status',
    ];
    final suffix = parts.isEmpty ? '' : ' (${parts.join(', ')})';
    return '$runtimeType: $message$suffix';
  }
}

/// The request was rejected because the caller is not authenticated — no
/// token, or one that is expired, malformed, or revoked.
class FlexDocsAuthException extends FlexDocsException {
  const FlexDocsAuthException(super.message, {super.code, super.status, super.cause});
}

/// The caller is authenticated but not allowed to do this. Usually a `dbRules`
/// or `storageRules` denial, or an auth route the project has switched off.
class FlexDocsPermissionException extends FlexDocsException {
  const FlexDocsPermissionException(super.message, {super.code, super.status, super.cause});
}

/// The document, collection, or project does not exist.
class FlexDocsNotFoundException extends FlexDocsException {
  const FlexDocsNotFoundException(super.message, {super.code, super.status, super.cause});
}

/// The request was malformed or failed validation, client-side or server-side.
class FlexDocsValidationException extends FlexDocsException {
  const FlexDocsValidationException(super.message, {super.code, super.status, super.cause});
}

/// Too many requests. Back off before retrying.
class FlexDocsRateLimitException extends FlexDocsException {
  const FlexDocsRateLimitException(super.message, {super.code, super.status, super.cause});
}

/// The server failed to handle a well-formed request. Retryable.
class FlexDocsServerException extends FlexDocsException {
  const FlexDocsServerException(super.message, {super.code, super.status, super.cause});
}

/// The request never reached the server, or its reply never arrived —
/// connection refused, DNS failure, TLS error, timeout. Distinct from every
/// other subtype in that nothing on the server happened, so retrying is safe
/// even for non-idempotent calls.
class FlexDocsNetworkException extends FlexDocsException {
  const FlexDocsNetworkException(super.message, {super.code, super.status, super.cause});
}

/// A file upload failed or was cancelled. Carries no HTTP status: uploads run
/// over the socket, not over HTTP.
class FlexDocsUploadException extends FlexDocsException {
  const FlexDocsUploadException(super.message, {super.code, super.cause});
}
