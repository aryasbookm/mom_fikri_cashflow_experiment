import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  const RestoreResult({required this.targetPath, this.restoredImageCount = 0});

  final String targetPath;
  final int restoredImageCount;
}

class BackupService {
  static const String lastBackupKey = 'last_backup_timestamp';
  static const String autoBackupEnabledKey = 'auto_backup_enabled';
  static const String lastAutoBackupKey = 'last_auto_backup_timestamp';
  static const String lastBackupDataCountKey = 'last_backup_data_count';

  static const String _zipEntryDbName = 'mom_fikri_cashflow_v2.db';
  static const String _zipEntryImagesDir = 'product_images';
  static const String _zipEntryManifest = 'manifest.json';
  static const int _zipFormatVersion = 2;
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
  };

  static Future<BackupResult> backupDatabase({bool shareAfter = true}) async {
    final dbPath = await DatabaseHelper.instance.getDatabasePath();
    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      throw Exception('Database tidak ditemukan');
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'mom_fikri_backup_$timestamp.zip';
    final zipBytes = await _buildBackupZipBytes(dbPath);

    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, fileName);
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(zipBytes, flush: true);

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
      await Share.shareXFiles([XFile(tempPath)], text: 'Backup Mom Fiqry');
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
    final fileName = 'mom_fikri_autobackup_$timestamp.zip';
    final docsDir = await getApplicationDocumentsDirectory();
    final autoDir = Directory(p.join(docsDir.path, 'auto_backups'));
    if (!autoDir.existsSync()) {
      autoDir.createSync(recursive: true);
    }

    final zipBytes = await _buildBackupZipBytes(dbPath);
    final targetPath = p.join(autoDir.path, fileName);
    await File(targetPath).writeAsBytes(zipBytes, flush: true);

    _applyRetention(autoDir, retention);
    await _updateLastBackupMetadata();
    return targetPath;
  }

  static Future<int> getCurrentDataCount() async {
    final Database db = await DatabaseHelper.instance.database;
    final txCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM transactions'),
        ) ??
        0;
    final productCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;
    final deletedCount =
        Sqflite.firstIntValue(
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
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.toLowerCase().endsWith('.zip') ||
                  file.path.toLowerCase().endsWith('.db'),
            )
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
    final files =
        autoDir
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.toLowerCase().endsWith('.zip') ||
                  file.path.toLowerCase().endsWith('.db'),
            )
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
    if (extension != '.db' && extension != '.zip') {
      throw Exception('Format file harus .zip atau .db');
    }
    if (extension == '.db') {
      final dbBytes = await _readBackupBytes(sourcePath);
      return _restoreSnapshotFromDbBytes(dbBytes);
    }
    final zipBytes = await _readBackupBytes(sourcePath);
    return _restoreSnapshotFromZipBytes(zipBytes);
  }

  static Future<List<int>> _readBackupBytes(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception(
        'File backup tidak dapat diakses. Coba salin file ke folder Download lalu pilih ulang.',
      );
    }
    try {
      return await sourceFile.readAsBytes();
    } catch (error) {
      throw Exception(
        'Gagal membaca file backup dari sumber yang dipilih: $error',
      );
    }
  }

  static Future<RestoreResult> _restoreSnapshotFromDbBytes(
    List<int> dbBytes,
  ) async {
    return _replaceLocalData(
      dbBytes: dbBytes,
      imageFiles: null,
    );
  }

  static Future<RestoreResult> _restoreSnapshotFromZipBytes(
    List<int> zipBytes,
  ) async {
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    _validateBackupManifest(archive);

    final dbBytes = _resolveDbBytesFromArchive(archive);
    final imageFiles = _resolveImageBytesFromArchive(archive);

    return _replaceLocalData(
      dbBytes: dbBytes,
      imageFiles: imageFiles,
    );
  }

  static Future<RestoreResult> _replaceLocalData({
    required List<int> dbBytes,
    Map<String, List<int>>? imageFiles,
  }) async {
    await DatabaseHelper.instance.closeDatabase();

    final targetPath = await DatabaseHelper.instance.getDatabasePath();
    final targetFile = File(targetPath);

    final tempDir = await getTemporaryDirectory();
    final rollbackDbPath = p.join(
      tempDir.path,
      'restore_rollback_db_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final rollbackDbFile = File(rollbackDbPath);

    final imageDir = await _getProductImageDir();
    final rollbackImageDir = Directory(
      p.join(
        tempDir.path,
        'restore_rollback_images_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );

    final hadOriginalDb = await targetFile.exists();
    final hadOriginalImages = await imageDir.exists();

    if (await rollbackDbFile.exists()) {
      await rollbackDbFile.delete();
    }
    if (await rollbackImageDir.exists()) {
      await rollbackImageDir.delete(recursive: true);
    }

    if (hadOriginalDb) {
      try {
        await targetFile.rename(rollbackDbPath);
      } catch (error) {
        throw RestoreFailure(
          'Gagal menyiapkan rollback database. Restore dibatalkan.',
          rolledBack: false,
          cause: error,
        );
      }
    }

    if (hadOriginalImages) {
      try {
        await imageDir.rename(rollbackImageDir.path);
      } catch (error) {
        if (hadOriginalDb && await rollbackDbFile.exists()) {
          await rollbackDbFile.rename(targetPath);
        }
        throw RestoreFailure(
          'Gagal menyiapkan rollback folder foto. Restore dibatalkan.',
          rolledBack: false,
          cause: error,
        );
      }
    }

    try {
      final targetParentDir = Directory(p.dirname(targetPath));
      if (!await targetParentDir.exists()) {
        await targetParentDir.create(recursive: true);
      }
      try {
        await targetFile.writeAsBytes(dbBytes, flush: true);
      } catch (error) {
        throw RestoreFailure(
          'Gagal menulis file database backup ke lokasi aplikasi.',
          rolledBack: true,
          cause: 'target=$targetPath error=$error',
        );
      }
      var restoredImageCount = 0;
      if (imageFiles != null && imageFiles.isNotEmpty) {
        await imageDir.create(recursive: true);
        for (final entry in imageFiles.entries) {
          final safeName = p.basename(entry.key);
          final targetImagePath = p.join(imageDir.path, safeName);
          await File(targetImagePath).writeAsBytes(entry.value, flush: true);
          restoredImageCount += 1;
        }
      }

      final appVersion = DatabaseHelper.instance.getDatabaseVersion();
      final verifyDb = await openDatabase(targetPath, readOnly: true);
      final versionRows = await verifyDb.rawQuery('PRAGMA user_version');
      final tableRows = await verifyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('transactions','categories','products','transaction_items')",
      );
      await verifyDb.close();

      var restoredVersion = 0;
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
      final tableNames = <String>{};
      for (final row in tableRows) {
        final value = row['name'];
        if (value is String) {
          tableNames.add(value);
        }
      }
      const requiredBaseTables = <String>{
        'transactions',
        'categories',
        'products',
      };
      final missingBaseTables = requiredBaseTables.difference(tableNames);
      if (missingBaseTables.isNotEmpty) {
        throw RestoreFailure(
          'Struktur database tidak valid. Tabel wajib tidak lengkap: ${missingBaseTables.join(', ')}.',
          rolledBack: true,
        );
      }
      // transaction_items wajib untuk backup yang memang sudah v8.
      // Untuk backup versi lama (< v8), tabel ini akan dibuat otomatis via onUpgrade.
      final requiresItemsTable = restoredVersion >= 8;
      final hasItemsTable = tableNames.contains('transaction_items');
      final missingTables =
          requiresItemsTable && !hasItemsTable
              ? const <String>{'transaction_items'}
              : const <String>{};
      if (missingTables.isNotEmpty) {
        throw RestoreFailure(
          'Struktur database tidak valid. Tabel wajib tidak lengkap: ${missingTables.join(', ')}.',
          rolledBack: true,
        );
      }

      await DatabaseHelper.instance.database;
      if (await rollbackDbFile.exists()) {
        await rollbackDbFile.delete();
      }
      if (await rollbackImageDir.exists()) {
        await rollbackImageDir.delete(recursive: true);
      }
      return RestoreResult(
        targetPath: targetPath,
        restoredImageCount: restoredImageCount,
      );
    } catch (error) {
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        if (await imageDir.exists()) {
          await imageDir.delete(recursive: true);
        }
        if (hadOriginalDb && await rollbackDbFile.exists()) {
          await rollbackDbFile.rename(targetPath);
        }
        if (hadOriginalImages && await rollbackImageDir.exists()) {
          await rollbackImageDir.rename(imageDir.path);
        }
        await DatabaseHelper.instance.database;
      } catch (_) {
        // rollback best effort
      }
      if (error is RestoreFailure) {
        throw RestoreFailure(
          error.message,
          rolledBack: true,
          cause: error.cause ?? error,
        );
      }
      final detail = _restoreErrorDetail(error);
      throw RestoreFailure(
        'Restore gagal. Data dikembalikan ke versi sebelumnya. Penyebab: $detail',
        rolledBack: true,
        cause: error,
      );
    }
  }

  static String _restoreErrorDetail(Object error) {
    final raw = error.toString().replaceAll('\n', ' ').trim();
    if (raw.isEmpty) {
      return 'unknown error';
    }
    return raw.length > 220 ? '${raw.substring(0, 220)}...' : raw;
  }

  static void _validateBackupManifest(Archive archive) {
    final manifestEntry = archive.firstWhere(
      (entry) => _normalizeZipPath(entry.name) == _zipEntryManifest,
      orElse: () => ArchiveFile('', 0, <int>[]),
    );
    // Legacy zip backup (sebelum manifest) tetap didukung.
    if (manifestEntry.name.isEmpty || !manifestEntry.isFile) {
      return;
    }

    final content = manifestEntry.content;
    if (content is! List<int>) {
      throw RestoreFailure(
        'Format backup tidak dikenali (manifest rusak).',
        rolledBack: false,
      );
    }

    Map<String, dynamic> manifest;
    try {
      final decoded = jsonDecode(utf8.decode(content));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Manifest bukan object.');
      }
      manifest = decoded;
    } catch (_) {
      throw RestoreFailure(
        'Format backup tidak dikenali (manifest tidak valid).',
        rolledBack: false,
      );
    }

    final formatVersion = manifest['formatVersion'];
    const supportedVersions = <int>{1, _zipFormatVersion};
    if (formatVersion is! int || !supportedVersions.contains(formatVersion)) {
      throw RestoreFailure(
        'Format backup tidak didukung aplikasi ini.',
        rolledBack: false,
      );
    }
  }

  static Future<List<int>> _buildBackupZipBytes(String dbPath) async {
    final archive = Archive();

    final dbFile = File(dbPath);
    final dbBytes = await dbFile.readAsBytes();
    archive.addFile(ArchiveFile(_zipEntryDbName, dbBytes.length, dbBytes));

    final imageDir = await _getProductImageDir();
    if (imageDir.existsSync()) {
      final entries = imageDir.listSync(recursive: true);
      for (final entry in entries) {
        if (entry is! File) {
          continue;
        }
        final relativePath = p.relative(entry.path, from: imageDir.path);
        final zipEntryName = p.join(_zipEntryImagesDir, relativePath);
        final bytes = await entry.readAsBytes();
        archive.addFile(
          ArchiveFile(_normalizeZipPath(zipEntryName), bytes.length, bytes),
        );
      }
    }

    final manifest = <String, dynamic>{
      'formatVersion': _zipFormatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'dbEntry': _zipEntryDbName,
      'imageDirEntry': _zipEntryImagesDir,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile(_zipEntryManifest, manifestBytes.length, manifestBytes),
    );

    return ZipEncoder().encode(archive) ?? <int>[];
  }

  static String _normalizeZipPath(String path) {
    return path.replaceAll('\\', '/').replaceAll(RegExp('^/+'), '');
  }

  static Future<Directory> _getProductImageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, _zipEntryImagesDir));
  }

  static List<int> _resolveDbBytesFromArchive(Archive archive) {
    ArchiveFile? dbEntry;
    for (final entry in archive) {
      final normalized = _normalizeZipPath(entry.name).toLowerCase();
      if (!entry.isFile) {
        continue;
      }
      if (normalized == _zipEntryDbName.toLowerCase()) {
        dbEntry = entry;
        break;
      }
      if (normalized.endsWith('.db')) {
        dbEntry ??= entry;
      }
    }
    if (dbEntry == null) {
      throw RestoreFailure(
        'Isi backup .zip tidak valid (database tidak ditemukan).',
        rolledBack: false,
      );
    }
    final content = dbEntry.content;
    if (content is! List<int>) {
      throw RestoreFailure(
        'Isi backup .zip tidak valid (database rusak).',
        rolledBack: false,
      );
    }
    return content;
  }

  static Map<String, List<int>> _resolveImageBytesFromArchive(Archive archive) {
    final imageFiles = <String, List<int>>{};
    for (final entry in archive) {
      if (!entry.isFile) {
        continue;
      }
      final normalized = _normalizeZipPath(entry.name);
      final ext = p.extension(normalized).toLowerCase();
      if (!_imageExtensions.contains(ext)) {
        continue;
      }
      final content = entry.content;
      if (content is! List<int>) {
        continue;
      }
      final fileName = p.basename(normalized);
      if (fileName.isEmpty) {
        continue;
      }
      imageFiles[fileName] = content;
    }
    return imageFiles;
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
