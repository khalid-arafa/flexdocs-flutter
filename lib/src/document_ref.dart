import 'dart:async';

import 'models/credentials.dart';
import 'models/api_response.dart';
import 'models/document_event.dart';
import 'api_client.dart';
import 'socket_service.dart';
import 'logger.dart';
import 'url_utils.dart';

/// Reference to a single document in a FlexDocs collection.
///
/// Provides CRUD operations and real-time watching.
class DocumentRef {
  final Credentials _credentials;
  final String _docPath;
  final ApiClient _apiClient;
  final SocketService _socketService;

  DocumentRef({
    required Credentials credentials,
    required String docPath,
    required ApiClient apiClient,
    required SocketService socketService,
  })  : _credentials = credentials,
        _docPath = _normalizePath(docPath),
        _apiClient = apiClient,
        _socketService = socketService;

  static String _normalizePath(String path) {
    var p = path;
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// The API URL for this document.
  String get url => '/projects/${_credentials.projectCode}/db/${encodePath(_docPath)}';

  /// Fetch the document data.
  Future<Map<String, dynamic>?> get() async {
    final response = await _apiClient.get(url: url);
    if (response.ok && response.data != null) {
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return response.data;
    }
    if (!response.ok) {
      logger.warn('Failed to get document $_docPath: ${response.error}');
    }
    return null;
  }

  /// Update the document by merging fields (partial update).
  Future<ApiResponse> update(Map<String, dynamic> data) async {
    return _apiClient.put(
      url: url,
      data: {'data': data, 'type': 'update'},
    );
  }

  /// Replace the entire document.
  Future<ApiResponse> replace(Map<String, dynamic> data) async {
    return _apiClient.put(
      url: url,
      data: {'data': data, 'type': 'replace'},
    );
  }

  /// Delete the document.
  Future<ApiResponse> delete() async {
    return _apiClient.delete(url: url);
  }

  /// Watch this document for real-time changes.
  ///
  /// Returns a [Stream] that first emits the current document state,
  /// then emits change events from the socket. Cancel the subscription
  /// to stop watching.
  Stream<DocumentChangeEvent> watch() {
    final controller = StreamController<DocumentChangeEvent>();

    // Fetch initial data, then pipe socket events
    get().then((data) {
      if (!controller.isClosed) {
        controller.add(DocumentChangeEvent(
          action: DocumentAction.update,
          doc: data,
        ));
      }

      final subscription = _socketService.watchDoc(_docPath).listen(
        (event) {
          if (!controller.isClosed) controller.add(event);
        },
        onError: (Object error) {
          if (!controller.isClosed) {
            controller.add(DocumentChangeEvent.error(error.toString()));
          }
        },
      );

      controller.onCancel = () {
        subscription.cancel();
      };
    }).catchError((Object error) {
      if (!controller.isClosed) {
        controller.add(DocumentChangeEvent.error(error.toString()));
      }
    });

    return controller.stream;
  }
}
