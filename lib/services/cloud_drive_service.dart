import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';

class CloudRestoreResult {
  const CloudRestoreResult({required this.fileId, required this.fileName});

  final String fileId;
  final String fileName;
}

class CloudDriveService {
  CloudDriveService();

  static const _scopes = [drive.DriveApi.driveAppdataScope];
  static const lastCloudBackupTimeKey = 'last_cloud_backup_time';

  Future<bool> uploadDatabaseBackup() async {
    final signIn = GoogleSignIn(scopes: _scopes);
    final account = await signIn.signIn();
    if (account == null) {
      return false;
    }
    final client = await signIn.authenticatedClient();
    if (client == null) {
      return false;
    }
    try {
      final dbPath = await DatabaseHelper.instance.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception('Database tidak ditemukan: $dbPath');
      }

      final api = drive.DriveApi(client);
      final timestamp = _formatTimestamp(DateTime.now());
      final remoteName = 'Backup_MomFiqry_$timestamp.db';
      final media = drive.Media(dbFile.openRead(), await dbFile.length());
      final file =
          drive.File()
            ..name = remoteName
            ..parents = ['appDataFolder'];

      await api.files.create(file, uploadMedia: media, $fields: 'id');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        lastCloudBackupTimeKey,
        DateTime.now().toIso8601String(),
      );
      return true;
    } finally {
      client.close();
    }
  }

  Future<bool> testConnection() async {
    return uploadDatabaseBackup();
  }

  Future<List<Map<String, dynamic>>> getCloudBackupList() async {
    final signIn = GoogleSignIn(scopes: _scopes);
    final account = await signIn.signIn();
    if (account == null) {
      return [];
    }
    final client = await signIn.authenticatedClient();
    if (client == null) {
      return [];
    }
    try {
      final api = drive.DriveApi(client);
      final list = await api.files.list(
        q: "'appDataFolder' in parents and trashed = false and name contains 'Backup_MomFiqry_' and name contains '.db'",
        orderBy: 'modifiedTime desc',
        spaces: 'appDataFolder',
        pageSize: 50,
        $fields: 'files(id,name,modifiedTime,size)',
      );
      final files = list.files ?? const <drive.File>[];
      debugPrint('Cloud backup list fetched: ${files.length} files');
      return files
          .where((file) => file.id != null && file.name != null)
          .map(
            (file) => <String, dynamic>{
              'id': file.id!,
              'name': file.name!,
              'modifiedTime': file.modifiedTime?.toIso8601String(),
              'size': file.size,
            },
          )
          .toList();
    } finally {
      client.close();
    }
  }

  Future<CloudRestoreResult?> restoreLatestDatabaseBackup({
    String? fileId,
  }) async {
    final signIn = GoogleSignIn(scopes: _scopes);
    final account = await signIn.signIn();
    if (account == null) {
      return null;
    }
    final client = await signIn.authenticatedClient();
    if (client == null) {
      return null;
    }

    File? rollbackFile;
    File? tempRestoreFile;
    try {
      final api = drive.DriveApi(client);
      String? targetFileId = fileId;
      String? targetFileName;
      if (targetFileId == null) {
        final list = await api.files.list(
          q: "'appDataFolder' in parents and trashed = false and name contains 'Backup_MomFiqry_' and name contains '.db'",
          orderBy: 'modifiedTime desc',
          spaces: 'appDataFolder',
          pageSize: 1,
          $fields: 'files(id,name,modifiedTime)',
        );
        final files = list.files ?? const [];
        if (files.isEmpty) {
          throw Exception('Backup cloud tidak ditemukan.');
        }
        final latest = files.first;
        targetFileId = latest.id;
        targetFileName = latest.name;
      }

      if (targetFileId == null) {
        throw Exception('ID backup cloud tidak valid.');
      }
      if (targetFileName == null) {
        final metadata =
            await api.files.get(targetFileId, $fields: 'id,name') as drive.File;
        if (metadata.name == null) {
          throw Exception('Metadata backup cloud tidak valid.');
        }
        targetFileName = metadata.name;
      }

      final mediaResponse = await api.files.get(
        targetFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (mediaResponse is! drive.Media) {
        throw Exception('Gagal mengunduh backup cloud.');
      }

      final tempDir = await getTemporaryDirectory();
      tempRestoreFile = File(p.join(tempDir.path, 'cloud_restore_temp.db'));
      final sink = tempRestoreFile.openWrite();
      await sink.addStream(mediaResponse.stream);
      await sink.flush();
      await sink.close();

      final dbPath = await DatabaseHelper.instance.getDatabasePath();
      final dbFile = File(dbPath);
      rollbackFile = File(
        p.join(
          tempDir.path,
          'cloud_restore_rollback_${DateTime.now().millisecondsSinceEpoch}.db',
        ),
      );
      if (await dbFile.exists()) {
        await dbFile.copy(rollbackFile.path);
      }

      await DatabaseHelper.instance.closeDatabase();
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await tempRestoreFile.copy(dbPath);
      await DatabaseHelper.instance.database;

      if (targetFileName == null) {
        throw Exception('Nama backup cloud tidak valid.');
      }
      return CloudRestoreResult(fileId: targetFileId, fileName: targetFileName);
    } catch (error) {
      try {
        if (rollbackFile != null && await rollbackFile.exists()) {
          final dbPath = await DatabaseHelper.instance.getDatabasePath();
          final dbFile = File(dbPath);
          await DatabaseHelper.instance.closeDatabase();
          if (await dbFile.exists()) {
            await dbFile.delete();
          }
          await rollbackFile.copy(dbPath);
          await DatabaseHelper.instance.database;
        }
      } catch (_) {
        // rollback best effort only
      }
      rethrow;
    } finally {
      try {
        if (tempRestoreFile != null && await tempRestoreFile.exists()) {
          await tempRestoreFile.delete();
        }
      } catch (_) {
        // ignore cleanup failures
      }
      try {
        if (rollbackFile != null && await rollbackFile.exists()) {
          await rollbackFile.delete();
        }
      } catch (_) {
        // ignore cleanup failures
      }
      client.close();
    }
  }

  String _formatTimestamp(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final h = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$y$m${d}_$h$min$s';
  }
}
