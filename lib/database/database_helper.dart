import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/password_hasher.dart';

class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  static const int _dbVersion = 8;
  static const String _dbName = 'mom_fikri_cashflow_v2.db';

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<String> getDatabasePath() async {
    final databasesPath = await getDatabasesPath();
    return join(databasesPath, _dbName);
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  int getDatabaseVersion() => _dbVersion;

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        pin TEXT NOT NULL,
        role TEXT NOT NULL,
        profile_image_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        description TEXT,
        date TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        product_id INTEGER,
        quantity INTEGER,
        FOREIGN KEY(category_id) REFERENCES categories(id),
        FOREIGN KEY(user_id) REFERENCES users(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE production (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        date TEXT NOT NULL,
        user_id INTEGER NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        unit_price INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        total INTEGER NOT NULL,
        FOREIGN KEY(transaction_id) REFERENCES transactions(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        price INTEGER NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE deleted_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        original_id INTEGER,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        category_id INTEGER,
        category TEXT,
        description TEXT,
        date TEXT NOT NULL,
        user_id INTEGER,
        product_id INTEGER,
        quantity INTEGER,
        deleted_at TEXT NOT NULL,
        deleted_by TEXT NOT NULL,
        reason TEXT NOT NULL
      )
    ''');

    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    await db.insert('users', {
      'username': 'admin',
      'pin': PasswordHasher.hash('1234'),
      'role': 'owner',
      'profile_image_path': null,
    });

    await db.insert('users', {
      'username': 'karyawan',
      'pin': PasswordHasher.hash('0000'),
      'role': 'staff',
      'profile_image_path': null,
    });

    await db.insert('categories', {
      'name': 'Penjualan Kue',
      'type': 'IN',
    });

    await db.insert('categories', {
      'name': 'Bahan Baku',
      'type': 'OUT',
    });

    await db.insert('categories', {
      'name': 'Operasional',
      'type': 'OUT',
    });

    await db.insert('categories', {
      'name': 'Gaji',
      'type': 'OUT',
    });

    final products = [
      {'name': 'Roti Sosis', 'price': 5000},
      {'name': 'Roti Pizza Mini', 'price': 5000},
      {'name': 'Roti Abon', 'price': 5000},
      {'name': 'Roti Pisang Coklat', 'price': 5000},
      {'name': 'Roti Keju', 'price': 5000},
      {'name': 'Roti Vanila', 'price': 5000},
      {'name': 'Roti Coklat', 'price': 5000},
      {'name': 'Roti Boy', 'price': 5000},
      {'name': 'Roti Sobek 3 Rasa', 'price': 25000},
      {'name': 'Roti Sobek Coklat', 'price': 25000},
      {'name': 'Roti Maros', 'price': 20000},
      {'name': 'Donat Coklat', 'price': 4000},
      {'name': 'Donat Mini', 'price': 25000},
      {'name': 'Donat Glaze isi 12', 'price': 50000},
      {'name': 'Donat Coklat isi 12', 'price': 40000},
      {'name': 'Bolu 3 Rasa', 'price': 30000},
      {'name': 'Bolu Mabel', 'price': 45000},
      {'name': 'Brownies Panggang', 'price': 40000},
      {'name': 'Brownies Kukus Keju Kecil', 'price': 45000},
      {'name': 'Brownies Kukus Keju Sedang', 'price': 55000},
      {'name': 'Brownies Kukus Keju Besar', 'price': 100000},
      {'name': 'Brownies Toping Kecil', 'price': 50000},
      {'name': 'Brownies Toping Sedang', 'price': 60000},
      {'name': 'Bento Cake', 'price': 50000},
      {'name': 'Tart', 'price': 110000},
      {'name': 'Tart Besar', 'price': 130000},
      {'name': 'Aneka Snack', 'price': 10000},
      {'name': 'Dempo Kacang', 'price': 19000},
      {'name': 'Dempo Gula Pasir', 'price': 15000},
      {'name': 'Kacang Telur', 'price': 35000},
      {'name': 'Kacang Sembunyi', 'price': 10000},
      {'name': 'Snack Besar', 'price': 50000},
    ];

    for (final product in products) {
      await db.insert('products', {
        'name': product['name'],
        'price': product['price'],
        'min_stock': 5,
        'is_active': 0,
      });
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE users ADD COLUMN profile_image_path TEXT',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE deleted_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          original_id INTEGER,
          type TEXT NOT NULL,
          amount INTEGER NOT NULL,
          category_id INTEGER,
          category TEXT,
          description TEXT,
          date TEXT NOT NULL,
          user_id INTEGER,
          product_id INTEGER,
          quantity INTEGER,
          deleted_at TEXT NOT NULL,
          deleted_by TEXT NOT NULL,
          reason TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE deleted_transactions ADD COLUMN category_id INTEGER',
      );
      await db.execute(
        'ALTER TABLE deleted_transactions ADD COLUMN user_id INTEGER',
      );
      await db.execute(
        'ALTER TABLE deleted_transactions ADD COLUMN product_id INTEGER',
      );
      await db.execute(
        'ALTER TABLE deleted_transactions ADD COLUMN quantity INTEGER',
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN min_stock INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE products ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE transaction_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transaction_id INTEGER NOT NULL,
          product_id INTEGER,
          product_name TEXT NOT NULL,
          unit_price INTEGER NOT NULL,
          quantity INTEGER NOT NULL,
          total INTEGER NOT NULL,
          FOREIGN KEY(transaction_id) REFERENCES transactions(id),
          FOREIGN KEY(product_id) REFERENCES products(id)
        )
      ''');
    }
  }

  Future<void> insertDeletedTransaction(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('deleted_transactions', row);
  }

  Future<List<Map<String, dynamic>>> getDeletedTransactions() async {
    final db = await database;
    return db.query(
      'deleted_transactions',
      orderBy: 'deleted_at DESC',
    );
  }

  Future<void> deleteDeletedTransaction(int id) async {
    final db = await database;
    await db.delete(
      'deleted_transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearDeletedTransactions() async {
    final db = await database;
    await db.delete('deleted_transactions');
  }
}
