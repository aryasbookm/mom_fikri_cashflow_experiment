import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class CloudDriveService {
  CloudDriveService();

  static const _scopes = [
    drive.DriveApi.driveAppdataScope,
  ];

  Future<bool> testConnection() async {
    final signIn = GoogleSignIn(scopes: _scopes);
    final account = await signIn.signIn();
    if (account == null) {
      return false;
    }
    final client = await signIn.authenticatedClient();
    if (client == null) {
      return false;
    }
    final api = drive.DriveApi(client);
    final bytes = Uint8List.fromList(utf8.encode('Koneksi Berhasil!'));
    final media = drive.Media(Stream.value(bytes), bytes.length);
    final file = drive.File()
      ..name = 'hello_cloud.txt'
      ..parents = ['appDataFolder'];
    await api.files.create(
      file,
      uploadMedia: media,
      $fields: 'id',
    );
    client.close();
    return true;
  }
}
