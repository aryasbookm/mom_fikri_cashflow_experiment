import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';
import '../utils/password_hasher.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  bool _isOwnerAuthenticated = false;
  DateTime? _ownerAuthExpiresAt;
  Timer? _ownerAuthTimer;

  static const Duration _ownerAuthDuration = Duration(minutes: 5);

  User? get currentUser => _currentUser;

  bool get isOwnerAuthenticated {
    if (_ownerAuthExpiresAt == null) {
      return false;
    }
    if (DateTime.now().isAfter(_ownerAuthExpiresAt!)) {
      _resetOwnerAuth(notify: false);
      return false;
    }
    return _isOwnerAuthenticated;
  }

  Future<bool> login(String username, String pin) async {
    final Database db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    if (result.isEmpty) {
      return false;
    }

    final userMap = Map<String, dynamic>.from(result.first);
    final storedPin = userMap['pin'] as String? ?? '';
    final hashedInput = PasswordHasher.hash(pin);

    if (storedPin == hashedInput) {
      _currentUser = User.fromMap(userMap);
      _resetOwnerAuth(notify: false);
      notifyListeners();
      return true;
    }

    if (PasswordHasher.isLegacyPlain(pin, storedPin)) {
      await db.update(
        'users',
        {'pin': hashedInput},
        where: 'id = ?',
        whereArgs: [userMap['id']],
      );
      userMap['pin'] = hashedInput;
      _currentUser = User.fromMap(userMap);
      _resetOwnerAuth(notify: false);
      notifyListeners();
      return true;
    }

    return false;
  }

  Future<bool> changePassword({
    required String currentPin,
    required String newPin,
  }) async {
    final user = _currentUser;
    if (user == null) {
      return false;
    }

    final storedPin = user.pin;
    if (!PasswordHasher.matches(currentPin, storedPin)) {
      return false;
    }

    final Database db = await DatabaseHelper.instance.database;
    final hashedNewPin = PasswordHasher.hash(newPin);
    await db.update(
      'users',
      {'pin': hashedNewPin},
      where: 'id = ?',
      whereArgs: [user.id],
    );

    _currentUser = user.copyWith(pin: hashedNewPin);
    notifyListeners();
    return true;
  }

  Future<bool> authenticateOwner(String pin) async {
    final user = _currentUser;
    if (user == null || user.role != 'owner') {
      return false;
    }
    final isValid = PasswordHasher.matches(pin, user.pin);
    if (!isValid) {
      return false;
    }
    _isOwnerAuthenticated = true;
    _ownerAuthExpiresAt = DateTime.now().add(_ownerAuthDuration);
    _ownerAuthTimer?.cancel();
    _ownerAuthTimer = Timer(_ownerAuthDuration, _resetOwnerAuth);
    notifyListeners();
    return true;
  }

  Future<void> updateProfileImagePath(String? path) async {
    final user = _currentUser;
    if (user == null) {
      return;
    }

    final Database db = await DatabaseHelper.instance.database;
    await db.update(
      'users',
      {'profile_image_path': path},
      where: 'id = ?',
      whereArgs: [user.id],
    );

    _currentUser = user.copyWith(profileImagePath: path);
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    _resetOwnerAuth(notify: false);
    notifyListeners();
  }

  void _resetOwnerAuth({bool notify = true}) {
    _isOwnerAuthenticated = false;
    _ownerAuthExpiresAt = null;
    _ownerAuthTimer?.cancel();
    _ownerAuthTimer = null;
    if (notify) {
      notifyListeners();
    }
  }
}
