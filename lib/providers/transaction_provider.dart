import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/deleted_transaction_model.dart';
import '../models/transaction_model.dart';
import 'product_provider.dart';

class TransactionProvider extends ChangeNotifier {

  final List<TransactionModel> _transactions = [];
  final List<DeletedTransaction> _deletedTransactions = [];

  List<TransactionModel> get transactions => List.unmodifiable(_transactions);
  List<DeletedTransaction> get deletedTransactions =>
      List.unmodifiable(_deletedTransactions);

  void clearTransactions() {
    _transactions.clear();
    notifyListeners();
  }

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

  Future<void> deleteTransactionWithAudit({
    required TransactionModel transaction,
    required String reason,
    required String deletedBy,
    ProductProvider? productProvider,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.insertDeletedTransaction({
      'original_id': transaction.id,
      'type': transaction.type,
      'amount': transaction.amount,
      'category_id': transaction.categoryId,
      'category': transaction.categoryName,
      'description': transaction.description,
      'date': transaction.date,
      'user_id': transaction.userId,
      'product_id': transaction.productId,
      'quantity': transaction.quantity,
      'deleted_at': DateTime.now().toIso8601String(),
      'deleted_by': deletedBy,
      'reason': reason,
    });

    if (transaction.id != null) {
      await deleteTransaction(
        transaction.id!,
        productProvider: productProvider,
      );
    } else {
      await loadTransactions();
    }
  }

  Future<void> loadDeletedTransactions() async {
    final rows = await DatabaseHelper.instance.getDeletedTransactions();
    _deletedTransactions
      ..clear()
      ..addAll(rows.map(DeletedTransaction.fromMap));
    notifyListeners();
  }

  Future<void> deleteAuditLog(int id) async {
    await DatabaseHelper.instance.deleteDeletedTransaction(id);
    await loadDeletedTransactions();
  }

  Future<void> clearAllAuditLogs() async {
    await DatabaseHelper.instance.clearDeletedTransactions();
    await loadDeletedTransactions();
  }

  Future<bool> restoreDeletedTransaction(
    DeletedTransaction deleted, {
    ProductProvider? productProvider,
  }) async {
    final Database db = await DatabaseHelper.instance.database;
    int? categoryId = deleted.categoryId;
    if (categoryId == null && deleted.category != null) {
      final rows = await db.query(
        'categories',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [deleted.category],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        categoryId = rows.first['id'] as int?;
      }
    }

    if (categoryId == null) {
      return false;
    }

    await db.insert('transactions', {
      'type': deleted.type,
      'amount': deleted.amount,
      'category_id': categoryId,
      'description': deleted.description,
      'date': deleted.date,
      'user_id': deleted.userId,
      'product_id': deleted.productId,
      'quantity': deleted.quantity,
    });

    if ((deleted.type == 'IN' || deleted.type == 'WASTE') &&
        deleted.productId != null &&
        deleted.quantity != null) {
      await productProvider?.updateStock(deleted.productId!, -deleted.quantity!);
    }

    if (deleted.id != null) {
      await DatabaseHelper.instance.deleteDeletedTransaction(deleted.id!);
    }

    await loadTransactions();
    await loadDeletedTransactions();
    return true;
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
