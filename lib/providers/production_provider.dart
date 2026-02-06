import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/production_model.dart';

class ProductionProvider extends ChangeNotifier {
  final List<ProductionModel> _todayItems = [];

  List<ProductionModel> get todayItems => List.unmodifiable(_todayItems);

  int get totalQuantityToday {
    return _todayItems.fold(0, (sum, item) => sum + item.quantity);
  }


  Future<void> addProduction(ProductionModel item) async {
    final Database db = await DatabaseHelper.instance.database;
    await db.insert('production', item.toMap());
    await loadTodayProduction();
  }

  Future<void> loadTodayProduction() async {
    final Database db = await DatabaseHelper.instance.database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final result = await db.query(
      'production',
      where: 'date = ?',
      whereArgs: [today],
      orderBy: 'id DESC',
    );

    _todayItems
      ..clear()
      ..addAll(result.map(ProductionModel.fromMap));

    notifyListeners();
  }
}
