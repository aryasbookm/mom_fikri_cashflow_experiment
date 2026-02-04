import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  User? _currentUser;

  User? get currentUser => _currentUser;

  Future<bool> login(String username, String pin) async {
    final Database db = await DatabaseHelper.instance.database;

    final List<Map<String, dynamic>> result = await db.query(
      'users',
      where: 'username = ? AND pin = ?',
      whereArgs: [username, pin],
      limit: 1,
    );

    if (result.isEmpty) {
      return false;
    }

    _currentUser = User.fromMap(result.first);
    notifyListeners();
    return true;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}
