import 'models/credentials.dart';
import 'models/api_response.dart';
import 'api_client.dart';
import 'logger.dart';

/// Authentication service for FlexDocs.
///
/// Tokens are stateless JWTs with a long expiry, so "logging out" on this
/// client means discarding the token the app holds (the one it hands back from
/// `ApiClientOptions.getToken`). To end a session everywhere — on devices you
/// no longer hold — call [revokeTokens], which invalidates every token issued
/// to the account including the one making the call.
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
      url: '$_baseUrl/login-with-email',
      data: {'email': email, 'password': password},
    );
  }

  /// Register a new user with email and password.
  ///
  /// Roles are not settable here. Self-registration is anonymous, and the
  /// server ignores a client-supplied `roles` field. Assign roles from an
  /// admin-authenticated context instead.
  Future<ApiResponse> registerWithEmail({
    required String email,
    required String password,
    String? name,
    String? avatar,
  }) async {
    _validateEmail(email);
    _validatePassword(password);

    final data = <String, dynamic>{
      'email': email,
      'password': password,
    };
    if (name != null) data['name'] = name;
    if (avatar != null) data['avatar'] = avatar;

    return _apiClient.post(url: '$_baseUrl/register-with-email', data: data);
  }

  /// Login with an existing JWT token.
  Future<ApiResponse> loginWithToken({required String token}) async {
    if (token.isEmpty) {
      throw ArgumentError('Token cannot be empty');
    }

    return _apiClient.post(
      url: '$_baseUrl/login-with-token',
      data: {'token': token},
    );
  }

  /// Login anonymously as a guest.
  Future<ApiResponse> anonymousLogin({String? name, String? avatar}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (avatar != null) data['avatar'] = avatar;

    return _apiClient.post(url: '$_baseUrl/anonymous-login', data: data);
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
      url: '$_baseUrl/send-reset-password-email',
      data: {'email': email},
    );
  }

  /// Send an email verification to the current user.
  Future<ApiResponse> sendEmailVerification() async {
    return _apiClient.get(url: '$_baseUrl/send-email-verification');
  }

  // ---------------------------------------------------------------------------
  // Session lifetime
  // ---------------------------------------------------------------------------

  /// Exchange the current token for a fresh one with a full expiry window.
  ///
  /// Returns the new token, or null if the current one is no longer valid —
  /// expired, or revoked by a [revokeTokens] call from another device. A null
  /// return is the signal to send the user back to a login screen.
  ///
  /// The server re-verifies the presented token in full (signature, project
  /// binding, and the revocation counter) before issuing a replacement, so
  /// this can never launder a token that has already been invalidated.
  ///
  /// Call it from the `getToken` callback you give the SDK, or on app resume;
  /// there is no background refresh timer, by design — the SDK stores no
  /// tokens and so has nothing to refresh on your behalf.
  Future<String?> refreshToken() async {
    final response = await _apiClient.post(url: '$_baseUrl/refresh-token');
    if (!response.ok) {
      logger.warn('Token refresh failed: ${response.error}');
      return null;
    }
    final data = response.data;
    if (data is Map && data['token'] is String) return data['token'] as String;
    return null;
  }

  /// Invalidate every token ever issued to the signed-in account.
  ///
  /// This is "log out everywhere", and it deliberately includes the token used
  /// to make the call — there is no carve-out for the current session. Discard
  /// the token the app holds immediately afterwards; every subsequent request
  /// with it will be rejected.
  ///
  /// Backed by a counter on the account rather than a session store, so it is
  /// all-or-nothing: individual sessions cannot be revoked separately.
  Future<ApiResponse> revokeTokens() async {
    return _apiClient.post(url: '$_baseUrl/revoke-tokens');
  }

  /// Get the current authenticated user's profile.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final response = await _apiClient.get(url: '$_baseUrl/current-user');
      if (response.ok && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } catch (e) {
      logger.warn('Failed to get current user: $e');
      return null;
    }
  }
}
