import 'models/credentials.dart';
import 'models/api_response.dart';
import 'models/upload_progress.dart';
import 'api_client.dart';
import 'socket_service.dart';
import 'custom_upload.dart';
import 'url_utils.dart';

/// Storage service for file uploads, downloads, and bucket management.
class StorageService {
  final Credentials _credentials;
  final ApiClient _apiClient;
  final SocketService _socketService;

  StorageService({
    required Credentials credentials,
    required ApiClient apiClient,
    required SocketService socketService,
  })  : _credentials = credentials,
        _apiClient = apiClient,
        _socketService = socketService;

  String get _baseUrl => '/projects/${_credentials.projectCode}/storage';

  // ---------------------------------------------------------------------------
  // File operations
  // ---------------------------------------------------------------------------

  /// Upload one or more files.
  ///
  /// Returns a [CustomUpload] handle for tracking progress and awaiting results.
  CustomUpload upload({
    required List<UploadFileInfo> files,
    String? bucketId,
    bool autoDispose = true,
  }) {
    return CustomUpload(
      socketService: _socketService,
      files: files,
      bucketId: bucketId,
      autoDispose: autoDispose,
    );
  }

  /// Delete a file by its ID.
  Future<ApiResponse> deleteFile({required String fileId}) async {
    return _apiClient.delete(url: '$_baseUrl/files/${encodePathSegment(fileId)}');
  }

  /// Build a download URL for a file.
  ///
  /// [size] can be used for image resizing (e.g. `'200x200'`).
  String getFileUrl({
    required String fileId,
    required String filename,
    String? size,
    String? token,
  }) {
    final params = <String, String>{};
    if (size != null) params['size'] = size;
    if (token != null) params['token'] = token;

    final query = buildQueryString(params);
    final encodedId = encodePathSegment(fileId);
    final encodedName = encodePathSegment(filename);

    return '${_credentials.baseUrl}$_baseUrl/files/$encodedId/$encodedName$query';
  }

  // ---------------------------------------------------------------------------
  // Bucket operations
  // ---------------------------------------------------------------------------

  /// Create a new storage bucket.
  Future<ApiResponse> createBucket({
    required String name,
    String? description,
    String? parentId,
  }) async {
    final data = <String, dynamic>{'name': name};
    if (description != null) data['description'] = description;
    if (parentId != null) data['parentId'] = parentId;

    return _apiClient.post(url: '$_baseUrl/buckets', data: data);
  }

  /// Update a bucket's metadata.
  Future<ApiResponse> updateBucket({
    required String bucketId,
    String? name,
    String? description,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;

    return _apiClient.put(url: '$_baseUrl/buckets/${encodePathSegment(bucketId)}', data: data);
  }

  /// Delete a bucket and its contents.
  Future<ApiResponse> deleteBucket({required String bucketId}) async {
    return _apiClient.delete(url: '$_baseUrl/buckets/${encodePathSegment(bucketId)}');
  }

  /// Get the contents of a bucket (files and sub-buckets).
  Future<ApiResponse> getBucketContent({
    required String bucketId,
    int? page,
    int? ipp,
  }) async {
    final params = <String, dynamic>{};
    if (page != null) params['page'] = page;
    if (ipp != null) params['ipp'] = ipp;

    return _apiClient.get(
      url: '$_baseUrl/buckets/${encodePathSegment(bucketId)}/content',
      queryParameters: params.isNotEmpty ? params : null,
    );
  }

  /// Search for files and buckets.
  Future<ApiResponse> search({
    required String searchTerm,
    String? bucketId,
    int? page,
    int? ipp,
  }) async {
    final data = <String, dynamic>{'searchTerm': searchTerm};
    if (bucketId != null) data['bucketId'] = bucketId;
    if (page != null) data['page'] = page;
    if (ipp != null) data['ipp'] = ipp;

    return _apiClient.post(url: '$_baseUrl/search', data: data);
  }
}
