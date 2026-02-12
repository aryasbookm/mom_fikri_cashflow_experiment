import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';

class CloudRestoreResult {
  const CloudRestoreResult({required this.fileId, required this.fileName});

  final String fileId;
  final String fileName;
}

class CloudDriveService {
  CloudDriveService();

  static const _scopes = [drive.DriveApi.driveAppdataScope];
  static const int _maxCloudBackups = 10;
  static const String _backupQuery =
      "'appDataFolder' in parents and trashed = false and name contains 'Backup_MomFiqry_' and (name contains '.zip' or name contains '.db')";
  static const lastCloudBackupTimeKey = 'last_cloud_backup_time';
  static final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  static bool isNetworkError(Object error) {
    if (error is SocketException) {
      return true;
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('timed out');
  }

  static String userFriendlyMessage(
    Object error, {
    String fallback = 'Terjadi kendala saat terhubung ke Google Drive.',
  }) {
    if (isNetworkError(error)) {
      return 'Koneksi terputus. Pastikan internetmu aktif dan coba lagi.';
    }
    return fallback;
  }

  Future<void> disconnectAccount() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(lastCloudBackupTimeKey);
  }

  Future<bool> connectAccount() async {
    final account = await _googleSignIn.signIn();
    return account != null;
  }

  Future<bool> isSignedIn() async {
    if (_googleSignIn.currentUser != null) {
      return true;
    }
    final restored = await _googleSignIn.signInSilently();
    return restored != null;
  }

  Future<bool> uploadDatabaseBackup({bool includeImages = false}) async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return false;
    }
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      return false;
    }
    try {
      final localBackup = await BackupService.backupDatabase(
        shareAfter: false,
        includeImages: includeImages,
      );
      final backupFile = File(localBackup.tempPath);
      if (!await backupFile.exists()) {
        throw Exception('File backup tidak ditemukan: ${localBackup.tempPath}');
      }

      final api = drive.DriveApi(client);
      final timestamp = _formatTimestamp(DateTime.now());
      final remoteName = 'Backup_MomFiqry_$timestamp.zip';
      final media = drive.Media(
        backupFile.openRead(),
        await backupFile.length(),
      );
      final file =
          drive.File()
            ..name = remoteName
            ..parents = ['appDataFolder'];

      await api.files.create(file, uploadMedia: media, $fields: 'id');
      try {
        await _pruneOldBackups(api);
      } catch (error) {
        debugPrint('Cloud prune skipped due to error: $error');
      }
      await BackupService.markBackupSuccess();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        lastCloudBackupTimeKey,
        DateTime.now().toIso8601String(),
      );
      try {
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      } catch (_) {
        // ignore cleanup failures
      }
      return true;
    } finally {
      client.close();
    }
  }

  Future<bool> testConnection() async {
    return uploadDatabaseBackup();
  }

  Future<List<Map<String, dynamic>>> getCloudBackupList() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return [];
    }
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      return [];
    }
    try {
      final api = drive.DriveApi(client);
      final list = await api.files.list(
        q: _backupQuery,
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
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return null;
    }
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      return null;
    }

    File? tempRestoreFile;
    try {
      final api = drive.DriveApi(client);
      String? targetFileId = fileId;
      String? targetFileName;
      if (targetFileId == null) {
        final list = await api.files.list(
          q: _backupQuery,
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
      final resolvedFileName = targetFileName;
      if (resolvedFileName == null) {
        throw Exception('Nama backup cloud tidak valid.');
      }

      final mediaResponse = await api.files.get(
        targetFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (mediaResponse is! drive.Media) {
        throw Exception('Gagal mengunduh backup cloud.');
      }

      final tempDir = await getTemporaryDirectory();
      final fileExtension = p.extension(resolvedFileName).toLowerCase();
      final normalizedExt =
          fileExtension == '.zip' || fileExtension == '.db'
              ? fileExtension
              : '.db';
      tempRestoreFile = File(
        p.join(tempDir.path, 'cloud_restore_temp$normalizedExt'),
      );
      final sink = tempRestoreFile.openWrite();
      await sink.addStream(mediaResponse.stream);
      await sink.flush();
      await sink.close();

      await BackupService.restoreDatabaseFromPath(tempRestoreFile.path);

      return CloudRestoreResult(fileId: targetFileId, fileName: resolvedFileName);
    } catch (error) {
      rethrow;
    } finally {
      try {
        if (tempRestoreFile != null && await tempRestoreFile.exists()) {
          await tempRestoreFile.delete();
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

  Future<void> _pruneOldBackups(drive.DriveApi api) async {
    var pageToken = '';
    final all = <drive.File>[];
    do {
      final list = await api.files.list(
        q: _backupQuery,
        orderBy: 'modifiedTime desc',
        spaces: 'appDataFolder',
        pageSize: 100,
        pageToken: pageToken.isEmpty ? null : pageToken,
        $fields: 'nextPageToken, files(id,name,modifiedTime)',
      );
      final files = list.files ?? const <drive.File>[];
      all.addAll(files.where((f) => f.id != null));
      pageToken = list.nextPageToken ?? '';
    } while (pageToken.isNotEmpty);

    if (all.length <= _maxCloudBackups) {
      return;
    }
    final staleFiles = all.sublist(_maxCloudBackups);
    for (final file in staleFiles) {
      final id = file.id;
      if (id == null) {
        continue;
      }
      try {
        await api.files.delete(id);
      } catch (error) {
        debugPrint('Failed to prune cloud backup $id: $error');
      }
    }
  }
}
