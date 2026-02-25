import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mom_fikri_cashflow/services/ai_chatbot_service.dart';

void main() {
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
  });
}
