import 'models/credentials.dart';
import 'models/service_options.dart';
import 'models/api_client_options.dart';
import 'models/socket_options.dart';
import 'api_client.dart';
import 'socket_service.dart';
import 'db_service.dart';
import 'auth_service.dart';
import 'storage_service.dart';
import 'logger.dart';

/// Main entry point for the FlexDocs Flutter SDK.
///
/// Provides singleton access to Database, Auth, and Storage services:
/// ```dart
/// final db = FlexDocs.getDatabase(credentials);
/// final auth = FlexDocs.getAuth(credentials);
/// final storage = FlexDocs.getStorage(credentials);
///
/// // Clean up when done
/// FlexDocs.dispose();
/// ```
class FlexDocs {
  static ApiClient? _apiClient;
  static SocketService? _socketService;
  static DbService? _db;
  static AuthService? _auth;
  static StorageService? _storage;
  static Credentials? _credentials;

  // Prevent instantiation
  FlexDocs._();

  static ApiClient _getApiClient(
    Credentials creds,
    ApiClientOptions? options,
  ) {
    if (_apiClient == null || _credentials != creds) {
      _credentials = creds;
      _apiClient = ApiClient(
        credentials: creds,
        options: options ?? const ApiClientOptions(),
      );
    }
    return _apiClient!;
  }

  static SocketService _getSocketService(
    Credentials creds,
    SocketServiceOptions? options,
  ) {
    if (_socketService == null || _credentials != creds) {
      _credentials = creds;
      _socketService = SocketService(
        credentials: creds,
        options: options ?? const SocketServiceOptions(),
      );
    }
    return _socketService!;
  }

  /// Get the Database service singleton.
  static DbService getDatabase(
    Credentials creds, {
    ServiceOptions? options,
  }) {
    if (_db == null || _credentials != creds) {
      final apiClient = _getApiClient(creds, options?.apiOptions);
      final socketService = _getSocketService(creds, options?.socketOptions);
      _db = DbService(
        credentials: creds,
        apiClient: apiClient,
        socketService: socketService,
      );
    }
    return _db!;
  }

  /// Get the Auth service singleton.
  static AuthService getAuth(
    Credentials creds, {
    ServiceOptions? options,
  }) {
    if (_auth == null || _credentials != creds) {
      final apiClient = _getApiClient(creds, options?.apiOptions);
      _auth = AuthService(credentials: creds, apiClient: apiClient);
    }
    return _auth!;
  }

  /// Get the Storage service singleton.
  static StorageService getStorage(
    Credentials creds, {
    ServiceOptions? options,
  }) {
    if (_storage == null || _credentials != creds) {
      final apiClient = _getApiClient(creds, options?.apiOptions);
      final socketService = _getSocketService(creds, options?.socketOptions);
      _storage = StorageService(
        credentials: creds,
        apiClient: apiClient,
        socketService: socketService,
      );
    }
    return _storage!;
  }

  /// Connect the socket service for real-time features.
  static Future<void> connect() async {
    await _socketService?.connect();
  }

  /// Check if the socket is connected.
  static bool get isConnected => _socketService?.isConnected ?? false;

  /// Dispose all services and clean up resources.
  static void dispose() {
    _socketService?.close();
    _socketService = null;
    _apiClient = null;
    _db = null;
    _auth = null;
    _storage = null;
    _credentials = null;
    logger.info('FlexDocs disposed');
  }
}
