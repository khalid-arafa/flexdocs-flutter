/// Represents an authenticated user.
class AuthUser {
  final String? id;
  final String? email;
  final String? name;
  final String? avatar;
  final List<String>? roles;
  final String? token;
  final Map<String, dynamic> raw;

  const AuthUser({
    this.id,
    this.email,
    this.name,
    this.avatar,
    this.roles,
    this.token,
    this.raw = const {},
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['_id'] as String? ?? json['id'] as String?,
      email: json['email'] as String?,
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>(),
      token: json['token'] as String?,
      raw: json,
    );
  }

  @override
  String toString() => 'AuthUser(id: $id, email: $email)';
}
