import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/category_model.dart';

class CategoryProvider extends ChangeNotifier {
  CategoryProvider() {
    loadCategories();
  }

  final List<CategoryModel> _categories = [];
  String? _currentRole;

  List<CategoryModel> get categories => List.unmodifiable(_categories);

  void setCurrentRole(String? role) {
    _currentRole = role;
    notifyListeners();
  }

  Future<int> addCategory(String name, String type) async {
    final Database db = await DatabaseHelper.instance.database;
    final id = await db.insert('categories', {
      'name': name,
      'type': type,
    });
    await loadCategories();
    return id;
  }

  Future<void> loadCategories() async {
    final Database db = await DatabaseHelper.instance.database;
    final List<Map<String, dynamic>> result = await db.query('categories');

    _categories
      ..clear()
      ..addAll(result.map(CategoryModel.fromMap));

    notifyListeners();
  }

  List<CategoryModel> get incomeCategories {
    return _categories.where((cat) => cat.type == 'IN').toList();
  }

  List<CategoryModel> get expenseCategories {
    final expense = _categories.where((cat) => cat.type == 'OUT').toList();
    if (_currentRole != 'staff') {
      return expense;
    }

    const restricted = {'gaji', 'investasi', 'prive'};
    return expense
        .where((cat) => !restricted.contains(cat.name.toLowerCase().trim()))
        .toList();
  }
}
