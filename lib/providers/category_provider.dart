import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/default_categories.dart';
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
  final Map<int, bool> _categoryUsage = {};
  final Map<int, int> _categoryUsageCount = {};
  String? _currentRole;
  static final Set<String> _protectedCategoryNames =
      DefaultCategories.system
          .map((category) => category.normalizedName)
          .toSet();

  List<CategoryModel> get categories => List.unmodifiable(_categories);
  Map<int, bool> get categoryUsage => Map.unmodifiable(_categoryUsage);
  Map<int, int> get categoryUsageCount => Map.unmodifiable(_categoryUsageCount);

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

  Future<void> _ensureSystemCategories(Database db) async {
    for (final category in DefaultCategories.system) {
      final exists = await db.query(
        'categories',
        columns: ['id'],
        where: 'LOWER(TRIM(name)) = ? AND type = ?',
        whereArgs: [category.normalizedName, category.type],
        limit: 1,
      );
      if (exists.isEmpty) {
        await db.insert('categories', {
          'name': category.name,
          'type': category.type,
          'is_active': 1,
        });
      } else {
        final existingId = exists.first['id'] as int?;
        if (existingId != null) {
          await db.update(
            'categories',
            {'is_active': 1},
            where: 'id = ?',
            whereArgs: [existingId],
          );
        }
      }
    }
  }

  Future<void> _refreshCategoryUsage(Database db) async {
    _categoryUsage.clear();
    _categoryUsageCount.clear();

    final ids =
        _categories.map((category) => category.id).whereType<int>().toList();
    if (ids.isEmpty) {
      return;
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT category_id, COUNT(*) AS usage_count FROM transactions WHERE category_id IN ($placeholders) GROUP BY category_id',
      ids,
    );
    final usageById = <int, int>{};
    for (final row in rows) {
      final categoryId = row['category_id'];
      final usageCount = row['usage_count'];
      if (categoryId is int) {
        usageById[categoryId] =
            usageCount is int ? usageCount : int.tryParse('$usageCount') ?? 0;
      }
    }
    for (final id in ids) {
      final count = usageById[id] ?? 0;
      _categoryUsageCount[id] = count;
      _categoryUsage[id] = count > 0;
    }
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
      columns: ['id', 'is_active'],
      where: 'LOWER(TRIM(name)) = ? AND type = ?',
      whereArgs: [normalized.toLowerCase(), type],
      limit: 1,
    );
    if (exists.isNotEmpty) {
      final existingId = exists.first['id'] as int?;
      final isActive = (exists.first['is_active'] as int? ?? 1) == 1;
      if (existingId != null && !isActive) {
        await db.update(
          'categories',
          {'is_active': 1},
          where: 'id = ?',
          whereArgs: [existingId],
        );
        await loadCategories();
        return existingId;
      }
      throw Exception('Kategori sudah ada.');
    }
    final id = await db.insert('categories', {
      'name': normalized,
      'type': type,
      'is_active': 1,
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
      if (!category.isActive) {
        return const CategoryActionResult(
          success: false,
          message:
              'Kategori arsip yang sudah dipakai transaksi tidak dapat dihapus permanen.',
        );
      }
      await db.update(
        'categories',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [category.id],
      );
      await loadCategories();
      return const CategoryActionResult(
        success: true,
        message: 'Kategori disembunyikan dari input transaksi baru.',
      );
    }
    await db.delete('categories', where: 'id = ?', whereArgs: [category.id]);
    await loadCategories();
    return const CategoryActionResult(
      success: true,
      message: 'Kategori berhasil dihapus.',
    );
  }

  Future<CategoryActionResult> toggleCategoryActive({
    required CategoryModel category,
    required bool isActive,
  }) async {
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
        message: 'Kategori sistem tidak dapat diarsipkan.',
      );
    }
    if (category.isActive == isActive) {
      return CategoryActionResult(
        success: true,
        message:
            isActive
                ? 'Kategori sudah aktif.'
                : 'Kategori sudah berada di arsip.',
      );
    }
    await db.update(
      'categories',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [category.id],
    );
    await loadCategories();
    return CategoryActionResult(
      success: true,
      message:
          isActive
              ? 'Kategori berhasil diaktifkan.'
              : 'Kategori berhasil diarsipkan.',
    );
  }

  Future<void> loadCategories() async {
    final Database db = await DatabaseHelper.instance.database;
    await _ensureSystemCategories(db);
    final List<Map<String, dynamic>> result = await db.query('categories');

    _categories
      ..clear()
      ..addAll(result.map(CategoryModel.fromMap));
    await _refreshCategoryUsage(db);

    notifyListeners();
  }

  List<CategoryModel> get incomeCategories {
    return _categories
        .where((cat) => cat.type == 'IN' && cat.isActive)
        .toList();
  }

  List<CategoryModel> get expenseCategories {
    final expense =
        _categories.where((cat) => cat.type == 'OUT' && cat.isActive).toList();
    if (_currentRole != 'staff') {
      return expense;
    }

    const restricted = {'gaji', 'investasi', 'prive'};
    return expense
        .where((cat) => !restricted.contains(cat.name.toLowerCase().trim()))
        .toList();
  }
}
