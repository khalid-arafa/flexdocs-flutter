/// Configuration options for the Socket.IO service.
class SocketServiceOptions {
  /// Connection timeout in milliseconds.
  final int timeout;

  /// Whether to automatically reconnect on disconnect.
  final bool reconnection;

  /// Initial reconnection delay in milliseconds.
  final int reconnectionDelay;

  /// Maximum reconnection delay in milliseconds.
  final int reconnectionDelayMax;

  /// Maximum number of reconnection attempts.
  final int reconnectionAttempts;

  /// Chunk size in bytes for file uploads.
  final int chunkSize;

  /// Callback to provide a user authentication token.
  final Future<String?> Function()? getToken;

  /// Callback invoked when socket connects.
  final void Function()? onConnect;

  /// Callback invoked when socket disconnects.
  final void Function(String reason)? onDisconnect;

  /// Callback invoked on socket errors.
  final void Function(Object error)? onError;

  const SocketServiceOptions({
    this.timeout = 30000,
    this.reconnection = true,
    this.reconnectionDelay = 1000,
    this.reconnectionDelayMax = 5000,
    this.reconnectionAttempts = 999999,
    this.chunkSize = 65536,
    this.getToken,
    this.onConnect,
    this.onDisconnect,
    this.onError,
  });
}
