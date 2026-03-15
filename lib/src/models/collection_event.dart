/// Event emitted when a watched collection changes.
class CollectionChangeEvent {
  /// The full list of documents after the change (initial load or snapshot).
  final List<Map<String, dynamic>>? data;

  /// Documents that were added.
  final List<Map<String, dynamic>>? added;

  /// Documents that were updated.
  final List<Map<String, dynamic>>? updated;

  /// Documents that were removed.
  final List<Map<String, dynamic>>? removed;

  /// Error message if the watch encountered an error.
  final String? error;

  const CollectionChangeEvent({
    this.data,
    this.added,
    this.updated,
    this.removed,
    this.error,
  });

  factory CollectionChangeEvent.fromMap(Map<String, dynamic> map) {
    return CollectionChangeEvent(
      data: _castList(map['data']),
      added: _castList(map['added']),
      updated: _castList(map['updated']),
      removed: _castList(map['removed']),
      error: map['error'] as String?,
    );
  }

  factory CollectionChangeEvent.error(String message) {
    return CollectionChangeEvent(error: message);
  }

  static List<Map<String, dynamic>>? _castList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.cast<Map<String, dynamic>>();
    }
    return null;
  }

  @override
  String toString() =>
      'CollectionChangeEvent(data: ${data?.length}, added: ${added?.length}, '
      'updated: ${updated?.length}, removed: ${removed?.length}, error: $error)';
}
