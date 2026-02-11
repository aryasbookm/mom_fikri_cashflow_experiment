import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

class BackupResult {
  const BackupResult({
    required this.sourcePath,
    required this.tempPath,
    required this.downloadPath,
  });

  final String sourcePath;
  final String tempPath;
  final String? downloadPath;
}

class RestoreFailure implements Exception {
  RestoreFailure(this.message, {this.rolledBack = false, this.cause});

  final String message;
  final bool rolledBack;
  final Object? cause;

  @override
  String toString() => message;
}

class RestoreResult {
  const RestoreResult({
    required this.targetPath,
  });

  final String targetPath;
}

class BackupService {
  static const String lastBackupKey = 'last_backup_timestamp';
  static const String autoBackupEnabledKey = 'auto_backup_enabled';
  static const String lastAutoBackupKey = 'last_auto_backup_timestamp';
  static const String lastBackupDataCountKey = 'last_backup_data_count';

  static Future<BackupResult> backupDatabase({
    bool shareAfter = true,
  }) async {
    final dbPath = await DatabaseHelper.instance.getDatabasePath();
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      throw Exception('Database tidak ditemukan');
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'mom_fikri_backup_$timestamp.db';

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, fileName);
    final tempFile = await dbFile.copy(tempPath);

    final downloadDir = await _resolveDownloadDir();
    String? downloadPath;
    if (downloadDir != null) {
      try {
        if (!downloadDir.existsSync()) {
          downloadDir.createSync(recursive: true);
        }
        final targetPath = p.join(downloadDir.path, fileName);
        await tempFile.copy(targetPath);
        downloadPath = targetPath;
      } catch (_) {
        downloadPath = null;
      }
    }

    if (shareAfter) {
      await Share.shareXFiles(
        [XFile(tempPath)],
        text: 'Backup Mom Fiqry',
      );
    }

    await _updateLastBackupMetadata();

    return BackupResult(
      sourcePath: dbPath,
      tempPath: tempPath,
      downloadPath: downloadPath,
    );
  }

  static Future<String> autoBackupLocal({int retention = 5}) async {
    final dbPath = await DatabaseHelper.instance.getDatabasePath();
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      throw Exception('Database tidak ditemukan');
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'mom_fikri_autobackup_$timestamp.db';
    final docsDir = await getApplicationDocumentsDirectory();
    final autoDir = Directory(p.join(docsDir.path, 'auto_backups'));
    if (!autoDir.existsSync()) {
      autoDir.createSync(recursive: true);
    }
    final targetPath = p.join(autoDir.path, fileName);
    await dbFile.copy(targetPath);

    _applyRetention(autoDir, retention);
    await _updateLastBackupMetadata();
    return targetPath;
  }

  static Future<int> getCurrentDataCount() async {
    final Database db = await DatabaseHelper.instance.database;
    final txCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM transactions'),
        ) ??
        0;
    final productCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;
    final deletedCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM deleted_transactions'),
        ) ??
        0;
    return txCount + productCount + deletedCount;
  }

  static Future<bool> hasDataChanged() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = await getCurrentDataCount();
    final lastCount = prefs.getInt(lastBackupDataCountKey);
    if (lastCount == null) {
      return currentCount > 0;
    }
    return currentCount != lastCount;
  }

  static Future<void> markBackupSuccess() async {
    await _updateLastBackupMetadata();
  }

  static Future<void> _updateLastBackupMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(lastBackupKey, now);
    await prefs.setInt(lastAutoBackupKey, now);
    final currentCount = await getCurrentDataCount();
    await prefs.setInt(lastBackupDataCountKey, currentCount);
  }

  static void _applyRetention(Directory dir, int retention) {
    if (retention <= 0) {
      return;
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.db'))
        .toList();
    if (files.length <= retention) {
      return;
    }
    files.sort((a, b) {
      final aTime = a.lastModifiedSync();
      final bTime = b.lastModifiedSync();
      return aTime.compareTo(bTime);
    });
    final toDelete = files.length - retention;
    for (var i = 0; i < toDelete; i++) {
      try {
        files[i].deleteSync();
      } catch (_) {
        // ignore delete failures
      }
    }
  }

  static Future<RestoreResult?> restoreDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final picked = result.files.single;
    final sourcePath = picked.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw Exception('File backup tidak valid.');
    }
    return _restoreFromPath(sourcePath);
  }

  static Future<RestoreResult> restoreDatabaseFromPath(
    String sourcePath,
  ) async {
    return _restoreFromPath(sourcePath);
  }

  static Future<List<File>> getAutoBackupFiles({int limit = 5}) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final autoDir = Directory(p.join(docsDir.path, 'auto_backups'));
    if (!autoDir.existsSync()) {
      return [];
    }
    final files = autoDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.db'))
        .toList();
    files.sort((a, b) {
      final aTime = a.lastModifiedSync();
      final bTime = b.lastModifiedSync();
      return bTime.compareTo(aTime);
    });
    if (files.length <= limit) {
      return files;
    }
    return files.sublist(0, limit);
  }

  static Future<RestoreResult> _restoreFromPath(String sourcePath) async {
    final extension = p.extension(sourcePath).toLowerCase();
    if (extension != '.db') {
      throw Exception('Format file harus .db');
    }

    await DatabaseHelper.instance.closeDatabase();

    final targetPath = await DatabaseHelper.instance.getDatabasePath();
    final targetFile = File(targetPath);
    final tempPath = p.join(p.dirname(targetPath), 'v2_backup_temp.db');
    final tempFile = File(tempPath);

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final hadOriginal = await targetFile.exists();
    if (hadOriginal) {
      try {
        await targetFile.rename(tempPath);
      } catch (error) {
        throw RestoreFailure(
          'Gagal menyiapkan rollback. Restore dibatalkan.',
          rolledBack: false,
          cause: error,
        );
      }
    }

    try {
      await File(sourcePath).copy(targetPath);
      final appVersion = DatabaseHelper.instance.getDatabaseVersion();
      final verifyDb = await openDatabase(targetPath, readOnly: true);
      final versionRows = await verifyDb.rawQuery('PRAGMA user_version');
      final tableRows = await verifyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'",
      );
      await verifyDb.close();

      int restoredVersion = 0;
      if (versionRows.isNotEmpty) {
        final row = versionRows.first;
        final value = row.values.first;
        if (value is int) {
          restoredVersion = value;
        }
      }

      if (restoredVersion > appVersion) {
        throw RestoreFailure(
          'Versi backup terlalu baru untuk aplikasi ini.',
          rolledBack: true,
        );
      }
      if (tableRows.isEmpty) {
        throw RestoreFailure(
          'Struktur database tidak dikenali. Data lama dikembalikan.',
          rolledBack: true,
        );
      }

      await DatabaseHelper.instance.database;
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return RestoreResult(targetPath: targetPath);
    } catch (error) {
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        if (hadOriginal && await tempFile.exists()) {
          await tempFile.rename(targetPath);
        }
      } catch (_) {}
      throw RestoreFailure(
        'Restore gagal. Data dikembalikan ke versi sebelumnya.',
        rolledBack: true,
        cause: error,
      );
    }
  }

  static Future<Directory?> _resolveDownloadDir() async {
    if (Platform.isAndroid) {
      final candidates = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/self/primary/Download'),
      ];
      for (final dir in candidates) {
        if (dir.existsSync()) {
          return dir;
        }
      }
      return getExternalStorageDirectory();
    }

    if (Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }

    return getDownloadsDirectory();
  }
}
