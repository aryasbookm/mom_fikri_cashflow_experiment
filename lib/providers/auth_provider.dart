import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';
import '../utils/password_hasher.dart';

class AuthProvider extends ChangeNotifier {
  static const String _cachedUserIdKey = 'auth.cached_user_id';
  static const String _cachedUsernameKey = 'auth.cached_username';
  static const String _cachedRoleKey = 'auth.cached_role';
  static const String _biometricEnabledKey = 'auth.biometric_enabled';

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
      await _cacheBiometricSession(_currentUser!);
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
      await _cacheBiometricSession(_currentUser!);
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

  Future<bool> isBiometricQuickLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? true;
  }

  Future<void> setBiometricQuickLoginEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enabled);
  }

  Future<bool> hasBiometricSession() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_biometricEnabledKey) ?? true;
    final userId = prefs.getInt(_cachedUserIdKey);
    final username = prefs.getString(_cachedUsernameKey);
    final role = prefs.getString(_cachedRoleKey);
    if (!enabled || role != 'owner') {
      return false;
    }
    return userId != null || (username != null && username.trim().isNotEmpty);
  }

  Future<User?> loginWithBiometricSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_cachedUserIdKey);
    final username = prefs.getString(_cachedUsernameKey)?.trim();
    if (userId == null && (username == null || username.isEmpty)) {
      return null;
    }

    final Database db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> result =
        userId != null
            ? await db.query(
              'users',
              where: 'id = ?',
              whereArgs: [userId],
              limit: 1,
            )
            : await db.query(
              'users',
              where: 'username = ?',
              whereArgs: [username],
              limit: 1,
            );

    if (result.isEmpty) {
      await clearBiometricSession();
      return null;
    }

    final user = User.fromMap(result.first);
    if (user.role != 'owner') {
      await clearBiometricSession();
      return null;
    }
    _currentUser = user;
    _resetOwnerAuth(notify: false);
    notifyListeners();
    return _currentUser;
  }

  Future<void> clearBiometricSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedUserIdKey);
    await prefs.remove(_cachedUsernameKey);
    await prefs.remove(_cachedRoleKey);
    await prefs.setBool(_biometricEnabledKey, false);
  }

  Future<void> _cacheBiometricSession(User user) async {
    if (user.role != 'owner') {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (user.id != null) {
      await prefs.setInt(_cachedUserIdKey, user.id!);
    }
    await prefs.setString(_cachedUsernameKey, user.username);
    await prefs.setString(_cachedRoleKey, user.role);
    await prefs.setBool(_biometricEnabledKey, true);
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
