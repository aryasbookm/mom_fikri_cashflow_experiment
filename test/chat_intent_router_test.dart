import 'package:flutter_test/flutter_test.dart';
import 'package:mom_fikri_cashflow/services/chat_intent_router.dart';

void main() {
  group('ChatIntentRouter.normalize', () {
    test('normalizes abbreviations, slang, and regional tokens', () {
      final router = ChatIntentRouter();
      final normalized = router.normalize('Piro stokk yg blm lakuu??');

      expect(normalized, 'berapa stok yang belum lakuu');
    });

    test('collapses repeated chars before seed map matching', () {
      final router = ChatIntentRouter();
      final normalized = router.normalize('stokkkk pngeluaran');

      expect(normalized, 'stok pengeluaran');
    });
  });

  group('ChatIntentRouter.classify', () {
    final router = ChatIntentRouter();

    const cases = <_IntentCase>[
      // capability/help
      _IntentCase('kamu bisa apa?', ChatIntentType.capabilityHelp),
      _IntentCase('apa yang bisa kau lakukan', ChatIntentType.capabilityHelp),
      _IntentCase('fitur kamu apa saja', ChatIntentType.capabilityHelp),
      _IntentCase('cara pakai chatbot ini', ChatIntentType.capabilityHelp),
      _IntentCase('bisa bantu apa', ChatIntentType.capabilityHelp),
      _IntentCase('siapa nama mu?', ChatIntentType.capabilityHelp),
      _IntentCase('deskripsikan diri ku', ChatIntentType.capabilityHelp),
      _IntentCase('help', ChatIntentType.capabilityHelp),
      _IntentCase('apa kelebihan kamu', ChatIntentType.capabilityHelp),
      _IntentCase('apa batasan kamu', ChatIntentType.capabilityHelp),
      _IntentCase('keterbatasan kamu apa', ChatIntentType.capabilityHelp),

      // small talk
      _IntentCase('halo', ChatIntentType.smallTalk),
      _IntentCase('hai', ChatIntentType.smallTalk),
      _IntentCase('hi', ChatIntentType.smallTalk),
      _IntentCase('tes', ChatIntentType.smallTalk),
      _IntentCase('apa kabar', ChatIntentType.smallTalk),
      _IntentCase('gimana kabar', ChatIntentType.smallTalk),
      _IntentCase('terima kasih', ChatIntentType.smallTalk),
      _IntentCase('makasih', ChatIntentType.smallTalk),
      _IntentCase('assalamualaikum', ChatIntentType.smallTalk),
      _IntentCase('assalamulaikum', ChatIntentType.smallTalk),

      // import draft
      _IntentCase('tambah transaksi ini', ChatIntentType.importDraft),
      _IntentCase('tambahkan transaksi sekarang', ChatIntentType.importDraft),
      _IntentCase('import transaksi dari chat', ChatIntentType.importDraft),
      _IntentCase(
        'input transaksi ini untuk review',
        ChatIntentType.importDraft,
      ),
      _IntentCase(
        'buat draf transaksi dari daftar ini',
        ChatIntentType.importDraft,
      ),
      _IntentCase(
        'transaksi donat 20000 transaksi bolu 30000 transaksi roti 10000',
        ChatIntentType.importDraft,
      ),
      _IntentCase(
        'tambahkan pemasukan donat 100000 tanggal hari ini',
        ChatIntentType.importDraft,
      ),
      _IntentCase(
        'tambah pendapatan donat 100000 tanggal hari ini',
        ChatIntentType.importDraft,
      ),
      _IntentCase(
        'tambahkan pemasukan bansos 100k',
        ChatIntentType.importDraft,
      ),

      // stock
      _IntentCase('stoknya berapa selain yang 0', ChatIntentType.stockQuery),
      _IntentCase('sebutkan stok selain yang 0', ChatIntentType.stockQuery),
      _IntentCase('cek stok', ChatIntentType.stockQuery),
      _IntentCase('stok saat ini', ChatIntentType.stockQuery),
      _IntentCase('stok produk saat ini', ChatIntentType.stockQuery),
      _IntentCase('produk aktif saat ini', ChatIntentType.stockQuery),
      _IntentCase('produk yang diarsipkan', ChatIntentType.stockQuery),
      _IntentCase('urut stok tertinggi', ChatIntentType.stockQuery),
      _IntentCase('ranking stock terendah', ChatIntentType.stockQuery),
      _IntentCase('daftar sisa stok hari ini', ChatIntentType.stockQuery),
      _IntentCase('stok di atas 0 sebut', ChatIntentType.stockQuery),
      _IntentCase('brp stok roti maros', ChatIntentType.stockQuery),
      _IntentCase('stok produk tolong daftar', ChatIntentType.stockQuery),

      // date
      _IntentCase('penghasilan hari ini berapa', ChatIntentType.dateQuery),
      _IntentCase('pendapatan kemarin', ChatIntentType.dateQuery),
      _IntentCase('omset kemarin', ChatIntentType.dateQuery),
      _IntentCase('revenue kemarin', ChatIntentType.dateQuery),
      _IntentCase('income kemarin', ChatIntentType.dateQuery),
      _IntentCase('pengeluaran kemarin berapa', ChatIntentType.dateQuery),
      _IntentCase('biaya kemarin', ChatIntentType.dateQuery),
      _IntentCase('belanja kemarin', ChatIntentType.dateQuery),
      _IntentCase('cek pemasukan 4 hari lalu', ChatIntentType.dateQuery),
      _IntentCase('cek pemasukan 5 hari lalu', ChatIntentType.dateQuery),
      _IntentCase('penghasilan 7 hari terakhir', ChatIntentType.dateQuery),
      _IntentCase('penghasilan minggu lalu', ChatIntentType.dateQuery),
      _IntentCase('penghasilan bulan lalu', ChatIntentType.dateQuery),
      _IntentCase('penghasilan 24-02-2026', ChatIntentType.dateQuery),
      _IntentCase('penghasilan 2026-02-24', ChatIntentType.dateQuery),
      _IntentCase('penghasilan 24 Februari 2026', ChatIntentType.dateQuery),
      _IntentCase(
        'penghasilan dari 01-02-2026 sampai 15-02-2026',
        ChatIntentType.dateQuery,
      ),
      _IntentCase(
        'bandingkan transaksi 2 hari lalu dengan kemarin',
        ChatIntentType.dateQuery,
      ),
      _IntentCase('laba hari ini', ChatIntentType.dateQuery),
      _IntentCase(
        'banding penghasilan hari ini dan kemarin',
        ChatIntentType.dateQuery,
      ),
      _IntentCase(
        'perbandingan pengeluaran hari ini dan kemarin',
        ChatIntentType.dateQuery,
      ),
      _IntentCase(
        'compare pemasukan hari ini kemarin',
        ChatIntentType.dateQuery,
      ),

      // analysis
      _IntentCase('analisis laporan 30 hari', ChatIntentType.analysis),
      _IntentCase('kenapa laba turun minggu ini', ChatIntentType.analysis),
      _IntentCase('saran strategi untuk omzet', ChatIntentType.analysis),
      _IntentCase('rekomendasi prioritas minggu ini', ChatIntentType.analysis),
      _IntentCase('penyebab margin kecil', ChatIntentType.analysis),
      _IntentCase('kategori biaya terbesar apa', ChatIntentType.analysis),

      // outside scope
      _IntentCase('ramalan cuaca besok', ChatIntentType.outsideScope),
      _IntentCase('berita politik terbaru', ChatIntentType.outsideScope),
      _IntentCase('rekomendasi film lucu', ChatIntentType.outsideScope),
      _IntentCase('hasil bola malam ini', ChatIntentType.outsideScope),
      _IntentCase('kode program flutter', ChatIntentType.outsideScope),

      // ambiguous
      _IntentCase('cek', ChatIntentType.ambiguous),
      _IntentCase('cek ya', ChatIntentType.ambiguous),
      _IntentCase('tolong', ChatIntentType.ambiguous),
      _IntentCase('bantu', ChatIntentType.ambiguous),
      _IntentCase('yang tadi', ChatIntentType.ambiguous),

      // unknown
      _IntentCase('abc def ghi', ChatIntentType.unknown),
      _IntentCase('lihat itu yang ini maksudku', ChatIntentType.unknown),
      _IntentCase('hmm mungkin nanti', ChatIntentType.unknown),
      _IntentCase('sip lanjut', ChatIntentType.unknown),
    ];

    for (final testCase in cases) {
      test('classifies "${testCase.question}"', () {
        final decision = router.classify(testCase.question);
        expect(
          decision.type,
          testCase.expectedType,
          reason:
              'expected ${testCase.expectedType} for "${testCase.question}" '
              'but got ${decision.type} (${decision.reason})',
        );
      });
    }

    test('provides clarification options for ambiguous and unknown', () {
      final ambiguous = router.classify('cek');
      final unknown = router.classify('abc def ghi');

      expect(ambiguous.clarificationOptions, isNotEmpty);
      expect(unknown.clarificationOptions, isNotEmpty);
    });
  });
}

class _IntentCase {
  const _IntentCase(this.question, this.expectedType);

  final String question;
  final ChatIntentType expectedType;
}
