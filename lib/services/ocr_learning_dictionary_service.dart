import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';

class OcrLearningDictionaryService {
  static const String _storeKey = 'ocr_learning_dictionary_v1';
  static const String _seededKey = 'ocr_learning_dictionary_seeded_v1';
  static const int _maxEntries = 300;

  static Future<Map<String, String>> getDictionary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storeKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, String>{};
      }
      final map = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final value = (entry.value ?? '').toString().trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          map[key] = value;
        }
      }
      return map;
    } catch (_) {
      return <String, String>{};
    }
  }

  static String normalizeKey(String text) {
    final lowered = text.toLowerCase().trim();
    final stripped = lowered.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String applyCorrection(
    String description,
    Map<String, String> dictionary,
  ) {
    if (description.trim().isEmpty || dictionary.isEmpty) {
      return description.trim();
    }
    final normalizedFull = normalizeKey(description);
    final correctedFull = dictionary[normalizedFull];
    if (correctedFull != null && correctedFull.trim().isNotEmpty) {
      return correctedFull.trim();
    }

    final parts = description.split(',');
    if (parts.length <= 1) {
      return description.trim();
    }
    var changed = false;
    final correctedParts = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      final normalized = normalizeKey(trimmed);
      final corrected = dictionary[normalized];
      if (corrected != null && corrected.trim().isNotEmpty) {
        correctedParts.add(corrected.trim());
        if (corrected.trim() != trimmed) {
          changed = true;
        }
      } else {
        correctedParts.add(trimmed);
      }
    }
    if (!changed) {
      return description.trim();
    }
    return correctedParts.join(', ');
  }

  static Future<void> learnFromEdits(Map<String, String> rawToEdited) async {
    if (rawToEdited.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final current = await getDictionary();
    final updated = <String, String>{...current};

    for (final entry in rawToEdited.entries) {
      final raw = entry.key.trim();
      final edited = entry.value.trim();
      final key = normalizeKey(raw);
      if (key.isEmpty || edited.isEmpty) {
        continue;
      }
      if (normalizeKey(raw) == normalizeKey(edited)) {
        continue;
      }
      updated[key] = edited;
    }

    if (updated.length > _maxEntries) {
      final keys = updated.keys.toList();
      final removeCount = updated.length - _maxEntries;
      for (var i = 0; i < removeCount; i++) {
        updated.remove(keys[i]);
      }
    }

    await prefs.setString(_storeKey, jsonEncode(updated));
  }

  static Future<void> preloadFromProductsIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final seeded = prefs.getBool(_seededKey) ?? false;
    if (seeded) {
      return;
    }
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'products',
      columns: ['name'],
      where: 'name IS NOT NULL AND TRIM(name) != ?',
      whereArgs: [''],
      orderBy: 'is_active DESC, name ASC',
    );
    final current = await getDictionary();
    final updated = <String, String>{...current};

    for (final row in rows) {
      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }
      final fullKey = normalizeKey(name);
      if (fullKey.isNotEmpty && !updated.containsKey(fullKey)) {
        updated[fullKey] = name;
      }
    }

    await prefs.setString(_storeKey, jsonEncode(updated));
    await prefs.setBool(_seededKey, true);
  }
}
