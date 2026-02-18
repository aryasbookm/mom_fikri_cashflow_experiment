import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/category_model.dart';

class CategoryActionResult {
  const CategoryActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class CategoryProvider extends ChangeNotifier {
  CategoryProvider() {
    loadCategories();
  }

  final List<CategoryModel> _categories = [];
  String? _currentRole;
  static const Set<String> _protectedCategoryNames = {
    'penjualan kue',
    'pemasukan lain',
    'bahan baku',
    'operasional',
  };

  List<CategoryModel> get categories => List.unmodifiable(_categories);

  bool isProtectedCategory(CategoryModel category) {
    return _protectedCategoryNames.contains(category.name.toLowerCase().trim());
  }

  Future<bool> hasTransactions(int categoryId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT 1 FROM transactions WHERE category_id = ? LIMIT 1',
      [categoryId],
    );
    return result.isNotEmpty;
  }

  void setCurrentRole(String? role) {
    _currentRole = role;
    notifyListeners();
  }

  Future<int> addCategory(String name, String type) async {
    final Database db = await DatabaseHelper.instance.database;
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw Exception('Nama kategori wajib diisi.');
    }
    final exists = await db.query(
      'categories',
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = ? AND type = ?',
      whereArgs: [normalized.toLowerCase(), type],
      limit: 1,
    );
    if (exists.isNotEmpty) {
      throw Exception('Kategori sudah ada.');
    }
    final id = await db.insert('categories', {
      'name': normalized,
      'type': type,
    });
    await loadCategories();
    return id;
  }

  Future<CategoryActionResult> renameCategory({
    required CategoryModel category,
    required String newName,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final normalized = newName.trim();
    if (normalized.isEmpty) {
      return const CategoryActionResult(
        success: false,
        message: 'Nama kategori wajib diisi.',
      );
    }
    if (isProtectedCategory(category)) {
      return const CategoryActionResult(
        success: false,
        message: 'Kategori sistem tidak dapat diubah.',
      );
    }
    if (normalized.toLowerCase() == category.name.toLowerCase()) {
      return const CategoryActionResult(
        success: true,
        message: 'Tidak ada perubahan nama.',
      );
    }
    final duplicate = await db.query(
      'categories',
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = ? AND type = ? AND id != ?',
      whereArgs: [normalized.toLowerCase(), category.type, category.id],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      return const CategoryActionResult(
        success: false,
        message: 'Nama kategori sudah digunakan.',
      );
    }

    await db.update(
      'categories',
      {'name': normalized},
      where: 'id = ?',
      whereArgs: [category.id],
    );
    await loadCategories();
    return const CategoryActionResult(
      success: true,
      message: 'Kategori berhasil diubah.',
    );
  }

  Future<CategoryActionResult> deleteCategory(CategoryModel category) async {
    final db = await DatabaseHelper.instance.database;
    if (category.id == null) {
      return const CategoryActionResult(
        success: false,
        message: 'Kategori tidak valid.',
      );
    }
    if (isProtectedCategory(category)) {
      return const CategoryActionResult(
        success: false,
        message: 'Kategori sistem tidak dapat dihapus.',
      );
    }
    if (await hasTransactions(category.id!)) {
      return const CategoryActionResult(
        success: false,
        message:
            'Kategori sudah dipakai transaksi. Hapus ditolak untuk menjaga riwayat data.',
      );
    }
    await db.delete('categories', where: 'id = ?', whereArgs: [category.id]);
    await loadCategories();
    return const CategoryActionResult(
      success: true,
      message: 'Kategori berhasil dihapus.',
    );
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
