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
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      throw ArgumentError('baseUrl must start with http:// or https://');
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
