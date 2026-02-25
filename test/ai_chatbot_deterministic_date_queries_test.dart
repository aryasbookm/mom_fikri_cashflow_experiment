import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mom_fikri_cashflow/services/ai_chatbot_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AiChatbotService deterministic date queries', () {
    test(
      'answers income yesterday deterministically from daily_summary',
      () async {
        final service = AiChatbotService();
        final now = DateTime.now();
        final today = DateFormat('yyyy-MM-dd').format(now);
        final yesterday = DateFormat(
          'yyyy-MM-dd',
        ).format(now.subtract(const Duration(days: 1)));

        final reply = await service.askFinancialAssistant(
          question: 'berapa penghasilan kemarin?',
          financeSnapshot: [
            {
              'type': 'daily_summary',
              'date': today,
              'income': 300000,
              'expense': 100000,
            },
            {
              'type': 'daily_summary',
              'date': yesterday,
              'income': 250000,
              'expense': 120000,
            },
          ],
        );

        expect(reply.providerId, 'local-deterministic');
        expect(reply.confidenceLevel, 'high');
        expect(reply.executionPath, 'local');
        expect(reply.text.toLowerCase(), contains('penghasilan kemarin'));
        expect(reply.text, contains('250.000'));
      },
    );

    test('compares today and yesterday with deterministic delta', () async {
      final service = AiChatbotService();
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final yesterday = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));

      final reply = await service.askFinancialAssistant(
        question:
            'berapa penghasilan hari ini? berapa kemarin? bandingkan keduanya',
        financeSnapshot: [
          {
            'type': 'daily_summary',
            'date': today,
            'income': 500000,
            'expense': 200000,
          },
          {
            'type': 'daily_summary',
            'date': yesterday,
            'income': 300000,
            'expense': 150000,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('perbandingan'));
      expect(reply.text.toLowerCase(), contains('naik'));
      expect(reply.text, contains('200.000'));
    });

    test('returns guidance when yesterday data missing', () async {
      final service = AiChatbotService();
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);

      final reply = await service.askFinancialAssistant(
        question: 'bandingkan penghasilan hari ini dan kemarin',
        financeSnapshot: [
          {
            'type': 'daily_summary',
            'date': today,
            'income': 500000,
            'expense': 100000,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'medium');
      expect(reply.text.toLowerCase(), contains('data harian lengkap'));
      expect(reply.text.toLowerCase(), contains('kemarin=-'));
    });

    test('handles N days ago deterministically', () async {
      final service = AiChatbotService();
      final now = DateTime.now();
      final fourDaysAgo = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 4)));

      final reply = await service.askFinancialAssistant(
        question: 'cek pemasukan 4 hari lalu',
        financeSnapshot: [
          {
            'type': 'daily_summary',
            'date': fourDaysAgo,
            'income': 41000,
            'expense': 10000,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('4 hari lalu'));
      expect(reply.text, contains('41.000'));
    });

    test('handles rolling 7 hari terakhir deterministically', () async {
      final service = AiChatbotService();
      final now = DateTime.now();
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < 7; i++) {
        rows.add({
          'type': 'daily_summary',
          'date': DateFormat(
            'yyyy-MM-dd',
          ).format(now.subtract(Duration(days: i))),
          'income': 10000,
          'expense': 1000,
        });
      }

      final reply = await service.askFinancialAssistant(
        question: 'penghasilan 7 hari terakhir',
        financeSnapshot: rows,
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('7 hari terakhir'));
      expect(reply.text, contains('70.000'));
    });

    test('handles compare 2 hari lalu dengan kemarin', () async {
      final service = AiChatbotService();
      final now = DateTime.now();
      final twoDaysAgo = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 2)));
      final yesterday = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));

      final reply = await service.askFinancialAssistant(
        question: 'bandingkan transaksi 2 hari lalu dengan kemarin',
        financeSnapshot: [
          {
            'type': 'daily_summary',
            'date': twoDaysAgo,
            'income': 20000,
            'expense': 5000,
          },
          {
            'type': 'daily_summary',
            'date': yesterday,
            'income': 35000,
            'expense': 8000,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('perbandingan'));
      expect(reply.text, contains('20.000'));
      expect(reply.text, contains('35.000'));
    });

    test('handles explicit single date deterministically', () async {
      final service = AiChatbotService();
      const targetDate = '2026-02-24';

      final reply = await service.askFinancialAssistant(
        question: 'cek pemasukan 2026-02-24',
        financeSnapshot: const [
          {
            'type': 'daily_summary',
            'date': targetDate,
            'income': 88000,
            'expense': 12000,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('24 feb 2026'));
      expect(reply.text, contains('88.000'));
    });

    test('handles explicit range deterministically', () async {
      final service = AiChatbotService();
      final reply = await service.askFinancialAssistant(
        question: 'penghasilan dari 01-02-2026 sampai 03-02-2026',
        financeSnapshot: const [
          {
            'type': 'daily_summary',
            'date': '2026-02-01',
            'income': 10000,
            'expense': 1000,
          },
          {
            'type': 'daily_summary',
            'date': '2026-02-02',
            'income': 20000,
            'expense': 1000,
          },
          {
            'type': 'daily_summary',
            'date': '2026-02-03',
            'income': 30000,
            'expense': 1000,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('1 feb 2026 s.d. 3 feb 2026'));
      expect(reply.text, contains('60.000'));
    });
  });
}
