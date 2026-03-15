/// Information about a storage bucket.
class BucketInfo {
  final String? id;
  final String? name;
  final String? description;
  final String? parentId;
  final Map<String, dynamic> raw;

  const BucketInfo({
    this.id,
    this.name,
    this.description,
    this.parentId,
    this.raw = const {},
  });

  factory BucketInfo.fromJson(Map<String, dynamic> json) {
    return BucketInfo(
      id: json['_id'] as String? ?? json['id'] as String?,
      name: json['name'] as String?,
      description: json['description'] as String?,
      parentId: json['parentId'] as String?,
      raw: json,
    );
  }

  @override
  String toString() => 'BucketInfo(id: $id, name: $name)';
}

/// Information about a stored file.
class FileInfo {
  final String? id;
  final String? name;
  final String? url;
  final int? size;
  final String? mimeType;
  final String? bucketId;
  final Map<String, dynamic> raw;

  const FileInfo({
    this.id,
    this.name,
    this.url,
    this.size,
    this.mimeType,
    this.bucketId,
    this.raw = const {},
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      id: json['_id'] as String? ?? json['id'] as String?,
      name: json['name'] as String? ?? json['filename'] as String?,
      url: json['url'] as String?,
      size: json['size'] as int?,
      mimeType: json['mimeType'] as String? ?? json['type'] as String?,
      bucketId: json['bucketId'] as String?,
      raw: json,
    );
  }

  @override
  String toString() => 'FileInfo(id: $id, name: $name)';
}
