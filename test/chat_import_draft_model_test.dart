import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/models/chat_import_draft.dart';
import 'package:mom_fikri_cashflow/services/ai_chatbot_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ChatImportDraftItem.fromJson', () {
    test('forces inferred date to needsReview with deterministic warning', () {
      final item = ChatImportDraftItem.fromJson({
        'type': 'IN',
        'amount': 50000,
        'description': 'Bolu',
        'category_hint': 'Bolu',
        'date_iso': '2025-11-03',
        'date_source': 'inferred',
        'needs_review': false,
        'warning': '',
        'confidence': 88,
      });

      expect(item.dateSource, 'inferred');
      expect(item.needsReview, isTrue);
      expect(
        item.warning,
        contains('Tanggal diinferensi dari konteks, mohon konfirmasi manual.'),
      );
    });
  });

  group('ChatImportDraft.fromJson', () {
    test('applies smart math parser and adds review warning', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': '10.000 + 5.000',
            'description': 'Sosis',
            'category_hint': 'Snack',
            'date_iso': '2025-11-03',
            'date_source': 'explicit',
            'needs_review': false,
            'warning': '',
            'confidence': 90,
          },
        ],
      });

      expect(draft.transactions.length, 1);
      expect(draft.transactions.first.amount, 15000);
      expect(draft.transactions.first.needsReview, isTrue);
      expect(
        draft.transactions.first.warning,
        contains('Nominal gabungan dihitung otomatis oleh parser lokal.'),
      );
    });

    test('filters non-transaction lines into ignoredLines', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': 184000,
            'description': 'Uang Bersih',
            'category_hint': '',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 80,
          },
        ],
      });

      expect(draft.transactions, isEmpty);
      expect(draft.ignoredLines, contains('Uang Bersih'));
    });

    test('normalizes duplicated amount tokens like 20.00020.000', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': '20.00020.000',
            'description': 'Donat',
            'category_hint': 'Snack',
            'date_iso': '2025-11-04',
            'date_source': 'explicit',
            'needs_review': false,
            'warning': '',
            'confidence': 90,
          },
        ],
      });

      expect(draft.transactions.length, 1);
      expect(draft.transactions.first.amount, 20000);
    });

    test('infers dates deterministically for blocks around explicit date', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': 40000,
            'description': 'Subek, manis',
            'category_hint': 'Penjualan Kue',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 80,
          },
          {
            'type': 'IN',
            'amount': 50000,
            'description': 'Tawar, bolu',
            'category_hint': 'Penjualan Kue',
            'date_iso': '2025-11-04',
            'date_source': 'explicit',
            'needs_review': false,
            'warning': '',
            'confidence': 90,
          },
          {
            'type': 'IN',
            'amount': 30000,
            'description': 'Donat',
            'category_hint': 'Penjualan Kue',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 88,
          },
        ],
      });

      expect(draft.transactions.length, 3);
      expect(draft.transactions[0].dateIso, '2025-11-03');
      expect(draft.transactions[0].dateSource, 'inferred');
      expect(draft.transactions[0].needsReview, isTrue);
      expect(draft.transactions[2].dateIso, '2025-11-04');
      expect(draft.transactions[2].dateSource, 'inferred');
      expect(draft.transactions[2].needsReview, isTrue);
    });

    test('falls back to today when no date exists at all', () {
      final draft = ChatImportDraft.fromJson({
        'intent': 'import_transactions_draft',
        'source': 'chat_manual_import',
        'transactions': [
          {
            'type': 'IN',
            'amount': 20000,
            'description': 'Donat',
            'category_hint': 'Penjualan Kue',
            'date_iso': '',
            'date_source': 'unknown',
            'needs_review': false,
            'warning': '',
            'confidence': 80,
          },
        ],
      });

      expect(draft.transactions.length, 1);
      expect(draft.transactions.first.dateIso, isNotEmpty);
      expect(draft.transactions.first.dateSource, 'inferred');
      expect(draft.transactions.first.needsReview, isTrue);
      expect(
        draft.inferenceNotes.join(' ').toLowerCase(),
        contains('fallback'),
      );
    });
  });

  group('AiChatbotService deterministic stock ranking', () {
    test('returns sorted stock list and excludes zero when requested', () async {
      final service = AiChatbotService();
      final reply = await service.askFinancialAssistant(
        question:
            'berapa stok saat ini? urutkan dari yang tertinggi ke yang terendah tanpa menyebutkan yang saat ini 0',
        financeSnapshot: [
          {
            'type': 'product_catalog',
            'name': 'Donat',
            'stock_now': 12,
            'min_stock': 3,
            'is_active': true,
          },
          {
            'type': 'product_catalog',
            'name': 'Bolu Coklat',
            'stock_now': 30,
            'min_stock': 5,
            'is_active': true,
          },
          {
            'type': 'product_catalog',
            'name': 'Roti Tawar',
            'stock_now': 0,
            'min_stock': 2,
            'is_active': true,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.text, contains('Bolu Coklat: 30'));
      expect(reply.text, contains('Donat: 12'));
      expect(reply.text, isNot(contains('Roti Tawar')));
      expect(
        reply.text.indexOf('Bolu Coklat'),
        lessThan(reply.text.indexOf('Donat')),
      );
    });

    test(
      'answers stock query without ordering keywords and excludes zero stock',
      () async {
        final service = AiChatbotService();
        final reply = await service.askFinancialAssistant(
          question: 'sebutkan stoknya berapa selain yang 0',
          financeSnapshot: [
            {
              'type': 'product_catalog',
              'name': 'Bento Cake',
              'stock_now': 2,
              'min_stock': 3,
              'is_active': true,
            },
            {
              'type': 'product_catalog',
              'name': 'Roti Tawar',
              'stock_now': 0,
              'min_stock': 2,
              'is_active': true,
            },
          ],
        );

        expect(reply.providerId, 'local-deterministic');
        expect(reply.confidenceLevel, 'high');
        expect(reply.text, contains('Produk dengan stok lebih dari 0'));
        expect(reply.text, contains('Bento Cake: 2'));
        expect(reply.text, isNot(contains('Roti Tawar')));
        expect(reply.text, isNot(contains('Dasar data:')));
        expect(reply.text, isNot(contains('Aksi singkat:')));
      },
    );

    test(
      'handles phrase "sebutkan stok selain yang 0" deterministically',
      () async {
        final service = AiChatbotService();
        final reply = await service.askFinancialAssistant(
          question: 'sebutkan stok selain yang 0',
          financeSnapshot: [
            {
              'type': 'product_catalog',
              'name': 'Donat Mini',
              'stock_now': 5,
              'min_stock': 3,
              'is_active': true,
            },
            {
              'type': 'product_catalog',
              'name': 'Roti Maros',
              'stock_now': 6,
              'min_stock': 2,
              'is_active': true,
            },
            {
              'type': 'product_catalog',
              'name': 'Roti Tawar',
              'stock_now': 0,
              'min_stock': 1,
              'is_active': true,
            },
          ],
        );

        expect(reply.providerId, 'local-deterministic');
        expect(reply.confidenceLevel, 'high');
        expect(reply.text, contains('Produk dengan stok lebih dari 0'));
        expect(reply.text, contains('Donat Mini: 5'));
        expect(reply.text, contains('Roti Maros: 6'));
        expect(reply.text, isNot(contains('Roti Tawar')));
        expect(reply.text, isNot(contains('Dasar data:')));
        expect(reply.text, isNot(contains('Aksi singkat:')));
      },
    );

    test('handles short stock command "cek stok" deterministically', () async {
      final service = AiChatbotService();
      final reply = await service.askFinancialAssistant(
        question: 'cek stok',
        financeSnapshot: [
          {
            'type': 'product_catalog',
            'name': 'Donat Mini',
            'stock_now': 5,
            'is_active': 1,
          },
          {
            'type': 'product_catalog',
            'name': 'Roti Maros',
            'stock_now': 2,
            'is_active': 1,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('stok'));
      expect(reply.text, contains('Donat Mini'));
      expect(reply.text, isNot(contains('Maksud Anda yang mana')));
    });

    test('handles product status query for archived products', () async {
      final service = AiChatbotService();
      final reply = await service.askFinancialAssistant(
        question: 'produk yang diarsipkan',
        financeSnapshot: [
          {
            'type': 'product_catalog',
            'name': 'Donat Mini',
            'stock_now': 5,
            'is_active': 1,
          },
          {
            'type': 'product_catalog',
            'name': 'Brownies Lama',
            'stock_now': 0,
            'is_active': 0,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text, contains('Produk arsip saat ini'));
      expect(reply.text, contains('Brownies Lama'));
      expect(reply.text, isNot(contains('Donat Mini')));
    });

    test('handles smart search category with deterministic filter', () async {
      final service = AiChatbotService();
      final reply = await service.askFinancialAssistant(
        question: 'cari kategori pengeluaran di atas 50 ribu',
        financeSnapshot: const [
          {
            'type': 'expense_category_30d',
            'category': 'Bahan Baku',
            'total_amount': 120000,
          },
          {
            'type': 'expense_category_30d',
            'category': 'Operasional',
            'total_amount': 20000,
          },
        ],
      );

      expect(reply.providerId, 'local-deterministic');
      expect(reply.executionPath, 'local');
      expect(reply.text, contains('Hasil pencarian kategori'));
      expect(reply.text, contains('Bahan Baku'));
      expect(reply.text, isNot(contains('Operasional')));
    });
  });

  group('AiChatbotService capability intent', () {
    test('routes capability variant to local template response', () async {
      final service = AiChatbotService();
      final reply = await service.askFinancialAssistant(
        question: 'apa yang bisa kau lakukan?',
        financeSnapshot: const [],
      );

      expect(reply.providerId, 'local-smalltalk');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text, contains('Saya bisa membantu:'));
      expect(reply.text, contains('Batasan:'));
      expect(reply.text, isNot(contains('Dasar data:')));
      expect(reply.text, isNot(contains('Aksi singkat:')));
    });

    test('routes greeting with provider suffix to local smalltalk', () async {
      final service = AiChatbotService();
      final reply = await service.askFinancialAssistant(
        question: 'halo gemini',
        financeSnapshot: const [],
      );

      expect(reply.providerId, 'local-smalltalk');
      expect(reply.confidenceLevel, 'high');
      expect(reply.text.toLowerCase(), contains('halo'));
    });
  });
}
