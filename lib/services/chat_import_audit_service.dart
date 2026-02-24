import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatImportAuditInfo {
  const ChatImportAuditInfo({
    required this.hash,
    required this.savedAtMs,
    required this.itemCount,
    required this.totalAmount,
  });

  final String hash;
  final int savedAtMs;
  final int itemCount;
  final int totalAmount;

  DateTime get savedAt =>
      DateTime.fromMillisecondsSinceEpoch(savedAtMs, isUtc: true).toLocal();
}

class ChatImportAuditService {
  static const String _recordsKey = 'chat_import_audit_records_v1';
  static const int _maxRecords = 100;

  static Future<ChatImportAuditInfo?> findRecentDuplicate(
    String hash, {
    int windowHours = 72,
  }) async {
    if (hash.trim().isEmpty) {
      return null;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final cutoff = now - Duration(hours: windowHours).inMilliseconds;
    final records = await _loadRecords();
    for (final record in records) {
      final itemHash = (record['hash'] ?? '').toString();
      final savedAtMs = _toInt(record['saved_at_ms']);
      if (itemHash == hash && savedAtMs >= cutoff) {
        return ChatImportAuditInfo(
          hash: itemHash,
          savedAtMs: savedAtMs,
          itemCount: _toInt(record['item_count']),
          totalAmount: _toInt(record['total_amount']),
        );
      }
    }
    return null;
  }

  static Future<void> recordSaved({
    required String hash,
    required int itemCount,
    required int totalAmount,
  }) async {
    if (hash.trim().isEmpty) {
      return;
    }
    final records = await _loadRecords();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    records.insert(0, {
      'hash': hash,
      'saved_at_ms': now,
      'item_count': itemCount,
      'total_amount': totalAmount,
    });
    final trimmed = records.take(_maxRecords).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, jsonEncode(trimmed));
  }

  static Future<List<Map<String, dynamic>>> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .map(
            (item) =>
                item is Map<String, dynamic>
                    ? item
                    : item is Map
                    ? Map<String, dynamic>.from(item)
                    : <String, dynamic>{},
          )
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
