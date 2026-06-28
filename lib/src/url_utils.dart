/// Internal URL-building helpers.
///
/// Caller-supplied identifiers (collection/document ids, file names, bucket ids)
/// are percent-encoded before being placed into a request path, and obvious
/// path-traversal segments are rejected — so a value like `'../other'` or one
/// containing `?`/`#`/`/` can't escape the intended endpoint or inject query
/// parameters. The server still performs its own authorization; this is the
/// client-side guard.
library;

/// Percent-encode a single path segment, rejecting traversal segments.
String encodePathSegment(String segment) {
  if (segment == '.' || segment == '..') {
    throw ArgumentError('Invalid path segment: "$segment"');
  }
  // Uri.encodeComponent encodes '/', '?', '#', '&', spaces, etc.
  return Uri.encodeComponent(segment);
}

/// Encode a multi-segment path such as `"collection/docId"`, preserving the
/// `/` separators while encoding each segment and dropping empty segments.
String encodePath(String path) {
  return path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(encodePathSegment)
      .join('/');
}

/// Build an encoded query string (including the leading `?`) from a map, or an
/// empty string when there are no params.
String buildQueryString(Map<String, String> params) {
  if (params.isEmpty) return '';
  final encoded = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  return '?$encoded';
}
