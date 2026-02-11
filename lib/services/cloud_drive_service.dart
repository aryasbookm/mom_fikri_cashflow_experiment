import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../database/database_helper.dart';

class CloudDriveService {
  CloudDriveService();

  static const _scopes = [
    drive.DriveApi.driveAppdataScope,
  ];

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
      final file = drive.File()
        ..name = remoteName
        ..parents = ['appDataFolder'];

      await api.files.create(
        file,
        uploadMedia: media,
        $fields: 'id',
      );
      return true;
    } finally {
      client.close();
    }
  }

  Future<bool> testConnection() async {
    return uploadDatabaseBackup();
  }

  String _formatTimestamp(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final h = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '${y}${m}${d}_${h}${min}${s}';
  }
}
