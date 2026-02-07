import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';
import '../utils/password_hasher.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;

  User? get currentUser => _currentUser;

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
    notifyListeners();
  }
}
