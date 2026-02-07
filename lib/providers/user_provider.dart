import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';
import '../utils/password_hasher.dart';

class UserProvider extends ChangeNotifier {
  final List<User> _users = [];

  List<User> get users => List.unmodifiable(_users);

  Future<void> loadUsers() async {
    final Database db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'users',
      orderBy: 'role ASC, username ASC',
    );
    _users
      ..clear()
      ..addAll(rows.map(User.fromMap));
    notifyListeners();
  }

  Future<bool> createStaff({
    required String username,
    required String password,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    try {
      await db.insert('users', {
        'username': username,
        'pin': PasswordHasher.hash(password),
        'role': 'staff',
        'profile_image_path': null,
      });
      await loadUsers();
      return true;
    } on DatabaseException {
      return false;
    }
  }

  Future<bool> updateUsername({
    required int userId,
    required String username,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    try {
      final rows = await db.update(
        'users',
        {'username': username},
        where: 'id = ?',
        whereArgs: [userId],
      );
      if (rows > 0) {
        await loadUsers();
        return true;
      }
      return false;
    } on DatabaseException {
      return false;
    }
  }

  Future<void> updateProfileImagePath({
    required int userId,
    required String? path,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    await db.update(
      'users',
      {'profile_image_path': path},
      where: 'id = ?',
      whereArgs: [userId],
    );
    await loadUsers();
  }

  Future<void> resetPassword({
    required int userId,
    String defaultPassword = '123456',
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    await db.update(
      'users',
      {'pin': PasswordHasher.hash(defaultPassword)},
      where: 'id = ?',
      whereArgs: [userId],
    );
    await loadUsers();
  }

  Future<bool> deleteUserIfNoTransactions(int userId) async {
    final Database db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM transactions WHERE user_id = ?',
      [userId],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    if (count > 0) {
      return false;
    }
    await db.delete(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    );
    await loadUsers();
    return true;
  }
}
