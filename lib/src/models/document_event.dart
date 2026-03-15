/// Actions that can occur on a watched document.
enum DocumentAction { update, delete }

/// Event emitted when a watched document changes.
class DocumentChangeEvent {
  /// The action that occurred.
  final DocumentAction? action;

  /// The document data after the change.
  final Map<String, dynamic>? doc;

  /// Error message if the watch encountered an error.
  final String? error;

  const DocumentChangeEvent({
    this.action,
    this.doc,
    this.error,
  });

  factory DocumentChangeEvent.fromMap(Map<String, dynamic> map) {
    DocumentAction? action;
    final actionStr = map['action'] as String?;
    if (actionStr == 'update') action = DocumentAction.update;
    if (actionStr == 'delete') action = DocumentAction.delete;

    return DocumentChangeEvent(
      action: action,
      doc: map['doc'] as Map<String, dynamic>?,
      error: map['error'] as String?,
    );
  }

  factory DocumentChangeEvent.error(String message) {
    return DocumentChangeEvent(error: message);
  }

  @override
  String toString() => 'DocumentChangeEvent(action: $action, error: $error)';
}
