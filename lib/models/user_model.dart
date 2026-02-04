class User {
  final int? id;
  final String username;
  final String pin;
  final String role;

  User({
    this.id,
    required this.username,
    required this.pin,
    required this.role,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      username: map['username'] as String,
      pin: map['pin'] as String,
      role: map['role'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'pin': pin,
      'role': role,
    };
  }
}
