import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/product_model.dart';

class ProductProvider extends ChangeNotifier {
  ProductProvider() {
    loadProducts();
  }

  final List<ProductModel> _products = [];

  List<ProductModel> get products => List.unmodifiable(_products);

  List<ProductModel> get activeProducts =>
      _products.where((product) => product.isActive).toList();

  ProductModel? getById(int id) {
    for (final product in _products) {
      if (product.id == id) {
        return product;
      }
    }
    return null;
  }

  Future<void> loadProducts() async {
    final Database db = await DatabaseHelper.instance.database;
    final result = await db.query('products', orderBy: 'name ASC');

    _products
      ..clear()
      ..addAll(result.map(ProductModel.fromMap));

    notifyListeners();
  }

  Future<int> addProduct(
    String name,
    int price, {
    int minStock = 5,
    bool isActive = true,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    final id = await db.insert('products', {
      'name': name,
      'price': price,
      'stock': 0,
      'min_stock': minStock,
      'is_active': isActive ? 1 : 0,
    });
    await loadProducts();
    return id;
  }

  Future<void> updateProduct({
    required int id,
    required String name,
    required int price,
    required int minStock,
    required bool isActive,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    await db.update(
      'products',
      {
        'name': name,
        'price': price,
        'min_stock': minStock,
        'is_active': isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await loadProducts();
  }

  Future<void> updateProductsActive({
    required List<int> ids,
    required bool isActive,
  }) async {
    if (ids.isEmpty) {
      return;
    }
    final Database db = await DatabaseHelper.instance.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      'products',
      {'is_active': isActive ? 1 : 0},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    await loadProducts();
  }

  Future<bool> updateStock(int productId, int change) async {
    final Database db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'products',
      columns: ['stock', 'is_active'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (result.isEmpty) {
      return false;
    }
    final current = result.first['stock'] as int? ?? 0;
    final isActive = (result.first['is_active'] as int? ?? 1) == 1;
    final updated = current + change;
    if (updated < 0) {
      return false;
    }
    final updateData = <String, Object>{
      'stock': updated,
    };
    if (updated > 0 && !isActive) {
      updateData['is_active'] = 1;
    }
    await db.update(
      'products',
      updateData,
      where: 'id = ?',
      whereArgs: [productId],
    );
    await loadProducts();
    return true;
  }
}
