class User {
  final int? id;
  final String username;
  final String pin;
  final String role;
  final String? profileImagePath;

  User({
    this.id,
    required this.username,
    required this.pin,
    required this.role,
    this.profileImagePath,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      username: map['username'] as String,
      pin: map['pin'] as String,
      role: map['role'] as String,
      profileImagePath: map['profile_image_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'pin': pin,
      'role': role,
      'profile_image_path': profileImagePath,
    };
  }

  User copyWith({
    int? id,
    String? username,
    String? pin,
    String? role,
    String? profileImagePath,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      pin: pin ?? this.pin,
      role: role ?? this.role,
      profileImagePath: profileImagePath ?? this.profileImagePath,
    );
  }
}
