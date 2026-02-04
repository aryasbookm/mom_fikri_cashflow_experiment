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

  Future<int> addProduct(String name, int price) async {
    final Database db = await DatabaseHelper.instance.database;
    final id = await db.insert('products', {
      'name': name,
      'price': price,
      'stock': 0,
    });
    await loadProducts();
    return id;
  }

  Future<bool> updateStock(int productId, int change) async {
    final Database db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'products',
      columns: ['stock'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (result.isEmpty) {
      return false;
    }
    final current = result.first['stock'] as int? ?? 0;
    final updated = current + change;
    if (updated < 0) {
      return false;
    }
    await db.update(
      'products',
      {'stock': updated},
      where: 'id = ?',
      whereArgs: [productId],
    );
    await loadProducts();
    return true;
  }
}
