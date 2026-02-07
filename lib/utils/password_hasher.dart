import 'dart:convert';

import 'package:crypto/crypto.dart';

class PasswordHasher {
  static String hash(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  static bool matches(String input, String storedHashOrPlain) {
    if (storedHashOrPlain == input) {
      return true;
    }
    return storedHashOrPlain == hash(input);
  }

  static bool isLegacyPlain(String input, String storedHashOrPlain) {
    return storedHashOrPlain == input && storedHashOrPlain != hash(input);
  }
}
