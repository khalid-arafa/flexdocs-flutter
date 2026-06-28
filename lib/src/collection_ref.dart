import 'dart:async';

import 'models/credentials.dart';
import 'models/api_response.dart';
import 'models/query_options.dart';
import 'models/collection_event.dart';
import 'api_client.dart';
import 'socket_service.dart';
import 'document_ref.dart';
import 'logger.dart';
import 'url_utils.dart';

/// Reference to a collection in FlexDocs with a fluent query builder.
///
/// All query methods return `this` for chaining:
/// ```dart
/// final results = await db.col('users')
///   .where('age', WhereFilter(isGreaterThan: 18))
///   .sort('createdAt', SortDirection.descending)
///   .limit(20)
///   .get();
/// ```
class CollectionRef {
  final Credentials _credentials;
  final String _colPath;
  final ApiClient _apiClient;
  final SocketService _socketService;

  // Query state
  // ignore: prefer_final_fields
  Map<String, dynamic> _query = {};
  Map<String, int> _sort = {'createdAt': -1};
  dynamic _selectedFields;
  int _limit = 100;
  int _skip = 0;
  int? _page;
  int _itemsPerPage = 20;

  CollectionRef({
    required Credentials credentials,
    required String colPath,
    required ApiClient apiClient,
    required SocketService socketService,
  })  : _credentials = credentials,
        _colPath = _normalizePath(colPath),
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

  /// The API URL for this collection.
  String get url => '/projects/${_credentials.projectCode}/db/${encodePath(_colPath)}';

  // ---------------------------------------------------------------------------
  // Query builder (fluent, returns this)
  // ---------------------------------------------------------------------------

  /// Add a filter condition using a field name and [WhereFilter].
  CollectionRef where(String field, WhereFilter filter) {
    _query[field] = filter.toFilterValue();
    return this;
  }

  /// Add a raw MongoDB-style filter map.
  ///
  /// Useful for `$and`, `$or`, and complex nested queries:
  /// ```dart
  /// col.whereRaw({'\$or': [{'role': 'admin'}, {'isMod': true}]});
  /// ```
  CollectionRef whereRaw(Map<String, dynamic> filter) {
    _query.addAll(filter);
    return this;
  }

  /// Set the sort order.
  CollectionRef sort(String field, SortDirection direction) {
    _sort = {field: direction.value};
    return this;
  }

  /// Select specific fields to return.
  ///
  /// Accepts:
  /// - `Map<String, int>`: `{'name': 1, 'email': 1}`
  /// - `List<String>`: `['name', 'email']`
  /// - `String`: `'name email'` (space or comma separated)
  CollectionRef select(dynamic fields) {
    if (fields is Map) {
      _selectedFields = Map<String, int>.from(fields);
    } else if (fields is List) {
      final map = <String, int>{};
      for (final f in fields) {
        map[f.toString()] = 1;
      }
      _selectedFields = map;
    } else if (fields is String) {
      final parts = fields.split(RegExp(r'[,\s]+'));
      final map = <String, int>{};
      for (final f in parts) {
        if (f.isNotEmpty) map[f] = 1;
      }
      _selectedFields = map;
    }
    return this;
  }

  /// Set the maximum number of documents to return.
  CollectionRef limit(int count) {
    _limit = count;
    return this;
  }

  /// Skip a number of documents (offset-based pagination).
  ///
  /// Setting skip clears any page-based pagination.
  CollectionRef skip(int count) {
    _skip = count;
    _page = null;
    return this;
  }

  /// Set page-based pagination.
  CollectionRef page(int pageNum, [int itemsPerPage = 20]) {
    if (pageNum < 1) {
      throw ArgumentError('Page number must be >= 1');
    }
    _page = pageNum;
    _itemsPerPage = itemsPerPage;
    return this;
  }

  // ---------------------------------------------------------------------------
  // Query execution
  // ---------------------------------------------------------------------------

  /// Build the query body for API requests.
  Map<String, dynamic> _buildQueryBody() {
    final body = <String, dynamic>{
      'sort': _sort,
    };

    if (_query.isNotEmpty) {
      body['filter'] = _query;
    }

    if (_selectedFields != null) {
      body['select'] = _selectedFields;
    }

    if (_page != null) {
      body['page'] = _page;
      body['ipp'] = _itemsPerPage;
    } else {
      body['limit'] = _limit;
      body['skip'] = _skip;
    }

    return body;
  }

  /// Execute the query and return matching documents.
  Future<List<dynamic>> get() async {
    final response = await _apiClient.post(url: url, data: _buildQueryBody());
    if (response.ok && response.data != null) {
      if (response.data is List) return response.data as List;
      if (response.data is Map && response.data['data'] is List) {
        return response.data['data'] as List;
      }
    }
    if (!response.ok) {
      logger.warn('Failed to query collection $_colPath: ${response.error}');
    }
    return [];
  }

  /// Add a new document to the collection.
  Future<ApiResponse> add(Map<String, dynamic> data) async {
    return _apiClient.post(url: '$url/add', data: data);
  }

  /// Update multiple documents matching the filter.
  Future<ApiResponse> updateMany({
    required Map<String, dynamic> filter,
    required Map<String, dynamic> newData,
  }) async {
    return _apiClient.put(
      url: url,
      data: {'filter': filter, 'newData': newData},
    );
  }

  /// Delete multiple documents matching the filter.
  Future<ApiResponse> deleteMany({
    required Map<String, dynamic> filter,
  }) async {
    return _apiClient.delete(url: url, data: {'filter': filter});
  }

  /// Get available filter fields for this collection.
  Future<ApiResponse> getFilters() async {
    return _apiClient.get(url: '$url/filters');
  }

  /// Get a [DocumentRef] for a document within this collection.
  DocumentRef doc(String docId) {
    return DocumentRef(
      credentials: _credentials,
      docPath: '$_colPath/$docId',
      apiClient: _apiClient,
      socketService: _socketService,
    );
  }

  /// Watch this collection for real-time changes.
  ///
  /// Returns a [Stream] that first emits the current data snapshot,
  /// then emits change events from the socket.
  Stream<CollectionChangeEvent> watch() {
    final controller = StreamController<CollectionChangeEvent>();

    // Fetch initial data
    get().then((data) {
      if (!controller.isClosed) {
        final docs = data
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();
        controller.add(CollectionChangeEvent(data: docs));
      }

      final subscription = _socketService.watchCol(_colPath).listen(
        (event) {
          if (!controller.isClosed) controller.add(event);
        },
        onError: (Object error) {
          if (!controller.isClosed) {
            controller.add(CollectionChangeEvent.error(error.toString()));
          }
        },
      );

      controller.onCancel = () {
        subscription.cancel();
      };
    }).catchError((Object error) {
      if (!controller.isClosed) {
        controller.add(CollectionChangeEvent.error(error.toString()));
      }
    });

    return controller.stream;
  }
}
