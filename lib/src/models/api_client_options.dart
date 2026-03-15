/// Configuration options for the API client.
class ApiClientOptions {
  /// Request timeout in milliseconds.
  final int timeout;

  /// Number of retry attempts for failed requests.
  final int retryAttempts;

  /// Initial retry delay in milliseconds (doubles with each attempt).
  final int retryDelay;

  /// Callback to provide a user authentication token.
  final Future<String?> Function()? getToken;

  /// Callback invoked on request errors.
  final void Function(Object error)? onError;

  const ApiClientOptions({
    this.timeout = 30000,
    this.retryAttempts = 3,
    this.retryDelay = 1000,
    this.getToken,
    this.onError,
  });
}
