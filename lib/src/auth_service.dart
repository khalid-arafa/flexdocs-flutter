import 'models/credentials.dart';
import 'models/api_response.dart';
import 'api_client.dart';
import 'logger.dart';

/// Authentication service for FlexDocs.
class AuthService {
  final Credentials _credentials;
  final ApiClient _apiClient;

  AuthService({
    required Credentials credentials,
    required ApiClient apiClient,
  })  : _credentials = credentials,
        _apiClient = apiClient;

  String get _baseUrl => '/projects/${_credentials.projectCode}/auth';

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  void _validateEmail(String email) {
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      throw ArgumentError('Invalid email address');
    }
  }

  void _validatePassword(String password) {
    if (password.length < 6) {
      throw ArgumentError('Password must be at least 6 characters');
    }
  }

  // ---------------------------------------------------------------------------
  // Auth methods
  // ---------------------------------------------------------------------------

  /// Login with email and password.
  Future<ApiResponse> loginWithEmail({
    required String email,
    required String password,
  }) async {
    _validateEmail(email);
    _validatePassword(password);

    return _apiClient.post(
      url: '$_baseUrl/login',
      data: {'email': email, 'password': password},
    );
  }

  /// Register a new user with email and password.
  Future<ApiResponse> registerWithEmail({
    required String email,
    required String password,
    String? name,
    String? avatar,
    List<String>? roles,
  }) async {
    _validateEmail(email);
    _validatePassword(password);

    final data = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (name != null) data['name'] = name;
    if (avatar != null) data['avatar'] = avatar;
    if (roles != null) data['roles'] = roles;

    return _apiClient.post(url: '$_baseUrl/register', data: data);
  }

  /// Login with an existing JWT token.
  Future<ApiResponse> loginWithToken({required String token}) async {
    if (token.isEmpty) {
      throw ArgumentError('Token cannot be empty');
    }

    return _apiClient.post(
      url: '$_baseUrl/token-login',
      data: {'token': token},
    );
  }

  /// Login anonymously as a guest.
  Future<ApiResponse> anonymousLogin({String? name, String? avatar}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (avatar != null) data['avatar'] = avatar;

    return _apiClient.post(url: '$_baseUrl/anonymous', data: data);
  }

  /// Change the current user's password.
  Future<ApiResponse> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    _validatePassword(oldPassword);
    _validatePassword(newPassword);

    if (oldPassword == newPassword) {
      throw ArgumentError('New password must be different from old password');
    }

    return _apiClient.post(
      url: '$_baseUrl/change-password',
      data: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
  }

  /// Send a password reset email.
  Future<ApiResponse> sendResetPasswordEmail({required String email}) async {
    _validateEmail(email);

    return _apiClient.post(
      url: '$_baseUrl/reset-password',
      data: {'email': email},
    );
  }

  /// Send an email verification to the current user.
  Future<ApiResponse> sendEmailVerification() async {
    return _apiClient.get(url: '$_baseUrl/send-verification');
  }

  /// Get the current authenticated user's profile.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final response = await _apiClient.get(url: '$_baseUrl/me');
      if (response.ok && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } catch (e) {
      logger.warn('Failed to get current user: $e');
      return null;
    }
  }

  /// Logout the current user.
  Future<ApiResponse> logout() async {
    return _apiClient.post(url: '$_baseUrl/logout');
  }
}
