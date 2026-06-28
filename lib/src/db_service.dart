import 'models/credentials.dart';
import 'models/api_response.dart';
import 'api_client.dart';
import 'socket_service.dart';
import 'document_ref.dart';
import 'collection_ref.dart';
import 'url_utils.dart';

/// Database service providing document and collection operations.
class DbService {
  final Credentials _credentials;
  final ApiClient _apiClient;
  final SocketService _socketService;

  DbService({
    required Credentials credentials,
    required ApiClient apiClient,
    required SocketService socketService,
  })  : _credentials = credentials,
        _apiClient = apiClient,
        _socketService = socketService;

  String get _baseUrl => '/projects/${_credentials.projectCode}/db';

  /// Get a reference to a single document.
  ///
  /// [docPath] should be in the format `collectionName/documentId`.
  DocumentRef doc(String docPath) {
    if (docPath.isEmpty) {
      throw ArgumentError('Document path cannot be empty');
    }
    return DocumentRef(
      credentials: _credentials,
      docPath: docPath,
      apiClient: _apiClient,
      socketService: _socketService,
    );
  }

  /// Get a reference to a collection for querying.
  ///
  /// [colPath] should be the collection name, e.g. `'users'`.
  CollectionRef col(String colPath) {
    if (colPath.isEmpty) {
      throw ArgumentError('Collection path cannot be empty');
    }
    return CollectionRef(
      credentials: _credentials,
      colPath: colPath,
      apiClient: _apiClient,
      socketService: _socketService,
    );
  }

  /// List all collections.
  Future<ApiResponse> collections({
    Map<String, dynamic>? where,
    int? page,
    int? limit,
  }) async {
    final data = <String, dynamic>{};
    if (where != null) data['where'] = where;
    if (page != null) data['page'] = page;
    if (limit != null) data['limit'] = limit;

    return _apiClient.post(url: '$_baseUrl/collections', data: data);
  }

  /// Create a new collection.
  Future<ApiResponse> createCollection({required String name}) async {
    return _apiClient.post(
      url: '$_baseUrl/collections/new',
      data: {'name': name},
    );
  }

  /// Rename an existing collection.
  Future<ApiResponse> renameCollection({
    required String oldName,
    required String newName,
  }) async {
    return _apiClient.put(
      url: '$_baseUrl/collections/${encodePathSegment(oldName)}/rename',
      data: {'newName': newName},
    );
  }
}
