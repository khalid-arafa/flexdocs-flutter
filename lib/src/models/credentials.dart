/// Credentials required to connect to a FlexDocs project.
class Credentials {
  final String baseUrl;
  final String projectCode;
  final String projectToken;
  final String? projectName;

  Credentials({
    required this.baseUrl,
    required this.projectCode,
    required this.projectToken,
    this.projectName,
  }) {
    if (baseUrl.isEmpty) {
      throw ArgumentError('baseUrl is required');
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError('baseUrl must be an http:// or https:// URL');
    }
    // Require TLS in production. Plaintext http:// is only permitted for local
    // development (loopback hosts) — otherwise the projectToken and user JWT
    // would travel in cleartext and be trivially sniffable/MITM-able.
    final host = uri.host;
    final isLoopback = host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '127.0.0.1' ||
        host == '::1';
    if (uri.scheme == 'http' && !isLoopback) {
      throw ArgumentError(
        'baseUrl must use https:// (plaintext http:// is only allowed for localhost)',
      );
    }
    if (projectCode.isEmpty) {
      throw ArgumentError('projectCode is required');
    }
    if (projectToken.isEmpty) {
      throw ArgumentError('projectToken is required');
    }
  }

  /// Returns the base API URL for this project.
  String get projectUrl => '$baseUrl/projects/$projectCode';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Credentials &&
          baseUrl == other.baseUrl &&
          projectCode == other.projectCode &&
          projectToken == other.projectToken &&
          projectName == other.projectName;

  @override
  int get hashCode => Object.hash(baseUrl, projectCode, projectToken, projectName);

  @override
  String toString() => 'Credentials(project: $projectCode)';
}
