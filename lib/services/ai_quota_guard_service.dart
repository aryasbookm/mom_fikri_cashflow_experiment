import 'package:shared_preferences/shared_preferences.dart';

import 'ai_insight_service.dart';

class AiQuotaGuardState {
  const AiQuotaGuardState({
    required this.isBlocked,
    required this.isDailyLimit,
    required this.retryAfterSeconds,
    required this.message,
  });

  final bool isBlocked;
  final bool isDailyLimit;
  final int retryAfterSeconds;
  final String message;
}

class AiQuotaGuardService {
  static const _retryUntilKey = 'ai_quota_retry_until_ms';
  static const _dailyDateKey = 'ai_quota_daily_limit_date';
  static const _dailyMessageKey = 'ai_quota_daily_limit_message';

  static Future<void> recordRateLimit(AiRateLimitException error) async {
    final prefs = await SharedPreferences.getInstance();
    if (error.isDailyLimit) {
      await prefs.setString(_dailyDateKey, _todayKey());
      await prefs.setString(_dailyMessageKey, error.toString());
      await prefs.remove(_retryUntilKey);
      return;
    }

    final retrySeconds = error.retryAfterSeconds <= 0 ? 60 : error.retryAfterSeconds;
    final retryUntil = DateTime.now().millisecondsSinceEpoch + (retrySeconds * 1000);
    await prefs.setInt(_retryUntilKey, retryUntil);
  }

  static Future<AiQuotaGuardState> getState() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = _todayKey();

    final dailyDate = prefs.getString(_dailyDateKey);
    if (dailyDate == today) {
      final msg =
          (prefs.getString(_dailyMessageKey) ?? '').trim().isNotEmpty
              ? prefs.getString(_dailyMessageKey)!.trim()
              : 'Kuota AI hari ini habis. Coba lagi besok.';
      return AiQuotaGuardState(
        isBlocked: true,
        isDailyLimit: true,
        retryAfterSeconds: 0,
        message: msg,
      );
    }

    if (dailyDate != null && dailyDate != today) {
      await prefs.remove(_dailyDateKey);
      await prefs.remove(_dailyMessageKey);
    }

    final retryUntil = prefs.getInt(_retryUntilKey) ?? 0;
    if (retryUntil > now.millisecondsSinceEpoch) {
      final remain = ((retryUntil - now.millisecondsSinceEpoch) / 1000).ceil();
      return AiQuotaGuardState(
        isBlocked: true,
        isDailyLimit: false,
        retryAfterSeconds: remain,
        message: 'AI sedang istirahat. Coba lagi dalam $remain detik.',
      );
    }

    if (retryUntil > 0) {
      await prefs.remove(_retryUntilKey);
    }

    return const AiQuotaGuardState(
      isBlocked: false,
      isDailyLimit: false,
      retryAfterSeconds: 0,
      message: '',
    );
  }

  static String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}

