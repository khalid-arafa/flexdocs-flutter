import 'dart:typed_data';

/// Status of a file upload.
enum UploadStatus {
  pending,
  preparing,
  uploading,
  complete,
  error,
}

/// Progress information for a single file upload.
class UploadProgress {
  /// Unique key identifying this upload.
  final String key;

  /// Original filename.
  final String name;

  /// File size in bytes.
  final int size;

  /// Current upload status.
  final UploadStatus status;

  /// Upload progress as a percentage (0.0 - 100.0).
  final double progress;

  /// Error message if the upload failed.
  final String? error;

  /// URL of the uploaded file (available after completion).
  final String? url;

  const UploadProgress({
    required this.key,
    required this.name,
    required this.size,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.error,
    this.url,
  });

  UploadProgress copyWith({
    UploadStatus? status,
    double? progress,
    String? error,
    String? url,
  }) {
    return UploadProgress(
      key: key,
      name: name,
      size: size,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      url: url ?? this.url,
    );
  }

  @override
  String toString() =>
      'UploadProgress(name: $name, status: $status, progress: ${progress.toStringAsFixed(1)}%)';
}

/// Information about a file to be uploaded.
class UploadFileInfo {
  /// The filename.
  final String name;

  /// File size in bytes.
  final int size;

  /// MIME type of the file.
  final String? mimeType;

  /// The raw file bytes.
  final Uint8List bytes;

  UploadFileInfo({
    required this.name,
    required this.bytes,
    this.mimeType,
  }) : size = bytes.length;

  @override
  String toString() => 'UploadFileInfo(name: $name, size: $size)';
}
