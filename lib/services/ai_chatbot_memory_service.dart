import 'package:shared_preferences/shared_preferences.dart';

class AiChatbotMemory {
  const AiChatbotMemory({
    required this.preferredName,
    required this.preferredSalutation,
    required this.tone,
    required this.pendingName,
  });

  final String preferredName;
  final String preferredSalutation;
  final String tone;
  final String pendingName;

  bool get hasProfile =>
      preferredName.isNotEmpty || preferredSalutation.isNotEmpty;
  bool get hasPendingRename => pendingName.isNotEmpty;

  AiChatbotMemory copyWith({
    String? preferredName,
    String? preferredSalutation,
    String? tone,
    String? pendingName,
  }) {
    return AiChatbotMemory(
      preferredName: preferredName ?? this.preferredName,
      preferredSalutation: preferredSalutation ?? this.preferredSalutation,
      tone: tone ?? this.tone,
      pendingName: pendingName ?? this.pendingName,
    );
  }
}

class AiChatbotMemoryService {
  static const String _nameKey = 'ai_chat_memory_name_v1';
  static const String _salutationKey = 'ai_chat_memory_salutation_v1';
  static const String _toneKey = 'ai_chat_memory_tone_v1';
  static const String _pendingNameKey = 'ai_chat_memory_pending_name_v1';

  Future<AiChatbotMemory> loadMemory() async {
    final prefs = await SharedPreferences.getInstance();
    return AiChatbotMemory(
      preferredName: (prefs.getString(_nameKey) ?? '').trim(),
      preferredSalutation: (prefs.getString(_salutationKey) ?? '').trim(),
      tone: (prefs.getString(_toneKey) ?? '').trim(),
      pendingName: (prefs.getString(_pendingNameKey) ?? '').trim(),
    );
  }

  Future<void> saveMemory(AiChatbotMemory memory) async {
    final prefs = await SharedPreferences.getInstance();
    await _setOrRemove(prefs, _nameKey, memory.preferredName);
    await _setOrRemove(prefs, _salutationKey, memory.preferredSalutation);
    await _setOrRemove(prefs, _toneKey, memory.tone);
    await _setOrRemove(prefs, _pendingNameKey, memory.pendingName);
  }

  Future<void> clearMemory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_salutationKey);
    await prefs.remove(_toneKey);
    await prefs.remove(_pendingNameKey);
  }

  String renderMemoryForPrompt(AiChatbotMemory memory) {
    final lines = <String>[];
    if (memory.preferredName.isNotEmpty) {
      lines.add('- nama_panggilan: ${memory.preferredName}');
    }
    if (memory.preferredSalutation.isNotEmpty) {
      lines.add('- sapaan: ${memory.preferredSalutation}');
    }
    if (memory.tone.isNotEmpty) {
      lines.add('- gaya_jawaban: ${memory.tone}');
    }
    if (lines.isEmpty) {
      return '- (belum ada preferensi pengguna)';
    }
    return lines.join('\n');
  }

  Future<void> _setOrRemove(SharedPreferences prefs, String key, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return prefs.remove(key);
    }
    return prefs.setString(key, trimmed);
  }
}
