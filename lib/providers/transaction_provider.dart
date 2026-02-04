import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/transaction_model.dart';
import 'product_provider.dart';

class TransactionProvider extends ChangeNotifier {
  TransactionProvider() {
    loadTransactions();
  }

  final List<TransactionModel> _transactions = [];

  List<TransactionModel> get transactions => List.unmodifiable(_transactions);

  Future<void> loadTransactions() async {
    final Database db = await DatabaseHelper.instance.database;
    const query = '''
      SELECT
        t.id,
        t.type,
        t.amount,
        t.category_id,
        t.description,
        t.date,
        t.user_id,
        t.product_id,
        t.quantity,
        c.name AS category_name
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      ORDER BY t.date DESC, t.id DESC
    ''';
    final List<Map<String, dynamic>> result = await db.rawQuery(query);

    _transactions
      ..clear()
      ..addAll(result.map(TransactionModel.fromMap));

    notifyListeners();
  }

  int get totalIncome {
    return _transactions
        .where((tx) => tx.type == 'IN')
        .fold(0, (sum, tx) => sum + tx.amount);
  }

  int get totalExpense {
    return _transactions
        .where((tx) => tx.type == 'OUT')
        .fold(0, (sum, tx) => sum + tx.amount);
  }

  int get balance => totalIncome - totalExpense;

  Future<void> addTransaction(TransactionModel transaction) async {
    final Database db = await DatabaseHelper.instance.database;
    await db.insert('transactions', transaction.toMap());
    await loadTransactions();
  }

  Future<void> addWasteTransaction({
    required int productId,
    required int quantity,
    required int userId,
    required int categoryId,
    required String description,
    required String date,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    await db.insert('transactions', {
      'type': 'WASTE',
      'amount': 0,
      'category_id': categoryId,
      'description': description,
      'date': date,
      'user_id': userId,
      'product_id': productId,
      'quantity': quantity,
    });
    await loadTransactions();
  }

  Future<void> deleteTransaction(
    int id, {
    ProductProvider? productProvider,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final tx = TransactionModel.fromMap(rows.first);
      if ((tx.type == 'IN' || tx.type == 'WASTE') &&
          tx.productId != null &&
          tx.quantity != null) {
        await productProvider?.updateStock(tx.productId!, tx.quantity!);
      }
    }
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await loadTransactions();
  }

  Future<void> loadTodayTransactionsForUser(int userId) async {
    final Database db = await DatabaseHelper.instance.database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    const query = '''
      SELECT
        t.id,
        t.type,
        t.amount,
        t.category_id,
        t.description,
        t.date,
        t.user_id,
        t.product_id,
        t.quantity,
        c.name AS category_name
      FROM transactions t
      LEFT JOIN categories c ON t.category_id = c.id
      WHERE t.user_id = ? AND t.date = ? AND t.type != 'WASTE'
      ORDER BY t.date DESC, t.id DESC
    ''';
    final List<Map<String, dynamic>> result =
        await db.rawQuery(query, [userId, today]);

    _transactions
      ..clear()
      ..addAll(result.map(TransactionModel.fromMap));

    notifyListeners();
  }

  List<Map<String, dynamic>> getExpenseStatistics({DateTime? date}) {
    return _getStatisticsByType(
      type: 'OUT',
      date: date,
      colors: const [
        Colors.red,
        Colors.orange,
        Colors.deepOrange,
        Colors.amber,
        Colors.purple,
      ],
    );
  }

  List<Map<String, dynamic>> getIncomeStatistics({DateTime? date}) {
    return _getStatisticsByType(
      type: 'IN',
      date: date,
      colors: const [
        Colors.green,
        Colors.blue,
        Colors.teal,
        Colors.lightBlue,
        Colors.indigo,
      ],
    );
  }

  List<Map<String, dynamic>> _getStatisticsByType({
    required String type,
    required List<Color> colors,
    DateTime? date,
  }) {
    final Map<String, double> totalsByCategory = {};
    final DateTime target = date ?? DateTime.now();

    for (final tx in _transactions) {
      if (tx.type != type) {
        continue;
      }
      final txDate = DateTime.tryParse(tx.date);
      if (txDate == null ||
          txDate.year != target.year ||
          txDate.month != target.month) {
        continue;
      }
      final name = tx.categoryName ?? 'Lainnya';
      totalsByCategory[name] = (totalsByCategory[name] ?? 0) + tx.amount;
    }

    final entries = totalsByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return List.generate(entries.length, (index) {
      final entry = entries[index];
      return {
        'name': entry.key,
        'total': entry.value,
        'color': colors[index % colors.length],
      };
    });
  }
}
