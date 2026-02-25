class ChatIntentRouter {
  ChatIntentDecision classify(String question) {
    final normalized = normalize(question);
    if (normalized.isEmpty) {
      return ChatIntentDecision(
        type: ChatIntentType.unknown,
        confidence: 0.1,
        normalizedQuestion: normalized,
        reason: 'empty_question',
        clarificationOptions: _defaultClarificationOptions,
      );
    }

    if (_isCapabilityHelp(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.capabilityHelp,
        confidence: 0.96,
        normalizedQuestion: normalized,
        reason: 'capability_keyword_match',
        clarificationOptions: const [],
      );
    }

    if (_isSmallTalk(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.smallTalk,
        confidence: 0.95,
        normalizedQuestion: normalized,
        reason: 'smalltalk_keyword_match',
        clarificationOptions: const [],
      );
    }

    if (_isImportDraft(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.importDraft,
        confidence: 0.92,
        normalizedQuestion: normalized,
        reason: 'import_keyword_or_list_pattern',
        clarificationOptions: const [],
      );
    }

    if (_isStockQuery(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.stockQuery,
        confidence: 0.93,
        normalizedQuestion: normalized,
        reason: 'stock_keyword_match',
        clarificationOptions: const [],
      );
    }

    if (_isDateQuery(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.dateQuery,
        confidence: 0.92,
        normalizedQuestion: normalized,
        reason: 'date_metric_keyword_match',
        clarificationOptions: const [],
      );
    }

    if (_looksOutsideScope(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.outsideScope,
        confidence: 0.84,
        normalizedQuestion: normalized,
        reason: 'outside_scope_topic_match',
        clarificationOptions: _defaultClarificationOptions,
      );
    }

    if (_isAnalysisQuery(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.analysis,
        confidence: 0.8,
        normalizedQuestion: normalized,
        reason: 'analysis_keyword_match',
        clarificationOptions: const [],
      );
    }

    if (_isAmbiguous(normalized)) {
      return ChatIntentDecision(
        type: ChatIntentType.ambiguous,
        confidence: 0.4,
        normalizedQuestion: normalized,
        reason: 'ambiguous_short_or_unspecific',
        clarificationOptions: _defaultClarificationOptions,
      );
    }

    return ChatIntentDecision(
      type: ChatIntentType.unknown,
      confidence: 0.3,
      normalizedQuestion: normalized,
      reason: 'no_strong_signal',
      clarificationOptions: _defaultClarificationOptions,
    );
  }

  String normalize(String input) {
    var value = input.toLowerCase().trim();
    if (value.isEmpty) {
      return '';
    }

    value =
        value
            .replaceAll(
              RegExp(r'[`~!@#\$%\^&\*\(\)_\+=\[\]\{\}\\\|;:"<>,\?/]'),
              ' ',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    final tokens = value
        .split(' ')
        .where((token) => token.trim().isNotEmpty)
        .map(_normalizeToken)
        .toList(growable: false);

    final joined = tokens.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return joined;
  }

  String _normalizeToken(String token) {
    final collapsed = token.replaceAllMapped(
      RegExp(r'(.)\1{2,}'),
      (match) => '${match.group(1)}${match.group(1)}',
    );
    return _seedMap[collapsed] ?? collapsed;
  }

  bool _isCapabilityHelp(String q) {
    return q.contains('kamu bisa apa') ||
        q.contains('kau bisa apa') ||
        q.contains('anda bisa apa') ||
        q.contains('apa yang bisa kamu lakukan') ||
        q.contains('apa yang bisa kau lakukan') ||
        q.contains('fitur kamu') ||
        q.contains('fiturmu') ||
        q.contains('kemampuan kamu') ||
        q.contains('kemampuanmu') ||
        q.contains('bisa bantu apa') ||
        q.contains('bantuan') ||
        q.contains('cara pakai') ||
        q == 'help';
  }

  bool _isSmallTalk(String q) {
    const exact = <String>{
      'halo',
      'hai',
      'hi',
      'tes',
      'test',
      'apa kabar',
      'gimana kabar',
      'terima kasih',
      'makasih',
      'selamat pagi',
      'selamat siang',
      'selamat sore',
      'selamat malam',
    };
    if (exact.contains(q)) {
      return true;
    }
    return RegExp(
      r'^(halo|hai|hi|tes|test|apa kabar|gimana kabar|terima kasih|makasih)\b',
    ).hasMatch(q);
  }

  bool _isImportDraft(String q) {
    if (q.contains('tambahkan transaksi') ||
        q.contains('tambah transaksi') ||
        q.contains('import transaksi') ||
        q.contains('input transaksi ini') ||
        q.contains('buat draf transaksi')) {
      return true;
    }
    final lines = q.split(' ');
    final amountLike = RegExp(r'\d{3,}').hasMatch(q);
    return amountLike && lines.length >= 5 && q.contains('transaksi');
  }

  bool _isStockQuery(String q) {
    final hasStock =
        q.contains('stok') ||
        q.contains('stock') ||
        q.contains('sisa') ||
        q.contains('produk aktif') ||
        q.contains('produk arsip') ||
        q.contains('produk diarsipkan');
    final hasIntent =
        q.contains('berapa') ||
        q.contains('cek') ||
        q.contains('urut') ||
        q.contains('ranking') ||
        q.contains('tertinggi') ||
        q.contains('terendah') ||
        q.contains('selain') ||
        q.contains('di atas') ||
        q.contains('daftar') ||
        q.contains('sebut') ||
        q.contains('saat ini') ||
        q.contains('aktif') ||
        q.contains('arsip') ||
        q.contains('diarsipkan');
    return hasStock && (hasIntent || q == 'stok' || q == 'cek stok');
  }

  bool _isDateQuery(String q) {
    final hasDateRef =
        q.contains('hari ini') ||
        q.contains('kemarin') ||
        q.contains('hari lalu') ||
        q.contains('minggu ini') ||
        q.contains('minggu lalu') ||
        q.contains('bulan ini') ||
        q.contains('bulan lalu') ||
        q.contains('hari terakhir') ||
        q.contains('dari') && q.contains('sampai') ||
        RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b').hasMatch(q) ||
        RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(q) ||
        RegExp(
          r'\b\d{1,2}\s+(jan|feb|mar|apr|mei|jun|jul|agu|agt|sep|okt|nov|des|januari|februari|maret|april|juni|juli|agustus|september|oktober|november|desember)(\s+\d{4})?\b',
        ).hasMatch(q);
    final hasMetric =
        q.contains('penghasilan') ||
        q.contains('pemasukan') ||
        q.contains('pengeluaran') ||
        q.contains('laba') ||
        q.contains('selisih') ||
        q.contains('untung') ||
        q.contains('transaksi');
    final hasCompare =
        q.contains('banding') ||
        q.contains('compare') ||
        q.contains('perbandingan');
    return (hasDateRef && hasMetric) || (hasCompare && hasMetric);
  }

  bool _isAnalysisQuery(String q) {
    const keywords = <String>[
      'analisis',
      'kenapa',
      'penyebab',
      'saran',
      'strategi',
      'rekomendasi',
      'prioritas',
      'kategori',
      'margin',
      'omzet',
      'pemasukan',
      'pengeluaran',
      'transaksi',
      '30 hari',
      'laporan',
    ];
    final hit = keywords.where(q.contains).length;
    if (hit >= 1 && !_isCapabilityHelp(q) && !_isSmallTalk(q)) {
      return true;
    }
    return q.startsWith('cek ') &&
        (q.contains('pemasukan') ||
            q.contains('pengeluaran') ||
            q.contains('transaksi'));
  }

  bool _isAmbiguous(String q) {
    const ambiguousExact = <String>{
      'cek',
      'cek ya',
      'bantu dong',
      'tolong bantu',
      'gimana ya',
      'yang kemarin',
      'yang tadi',
      'tolong',
      'bantu',
    };
    if (ambiguousExact.contains(q)) {
      return true;
    }
    if (q.split(' ').length <= 2 &&
        (q.contains('cek') || q.contains('bantu') || q.contains('gimana'))) {
      return true;
    }
    return false;
  }

  bool _looksOutsideScope(String q) {
    const outsideKeywords = <String>[
      'cuaca',
      'politik',
      'presiden',
      'film',
      'lagu',
      'game',
      'bola',
      'kripto',
      'saham',
      'berita',
      'kode program',
      'coding',
      'travel',
      'resep masakan',
    ];
    const financeKeywords = <String>[
      'keuangan',
      'laba',
      'untung',
      'rugi',
      'pendapatan',
      'pemasukan',
      'pengeluaran',
      'biaya',
      'stok',
      'produk',
      'kategori',
      'kas',
      'penjualan',
      'transaksi',
      'omzet',
      'margin',
      'laporan',
    ];
    if (financeKeywords.any(q.contains)) {
      return false;
    }
    return outsideKeywords.any(q.contains);
  }
}

class ChatIntentDecision {
  const ChatIntentDecision({
    required this.type,
    required this.confidence,
    required this.normalizedQuestion,
    required this.reason,
    required this.clarificationOptions,
  });

  final ChatIntentType type;
  final double confidence;
  final String normalizedQuestion;
  final String reason;
  final List<String> clarificationOptions;
}

enum ChatIntentType {
  capabilityHelp,
  smallTalk,
  stockQuery,
  dateQuery,
  importDraft,
  analysis,
  outsideScope,
  ambiguous,
  unknown,
}

const List<String> _defaultClarificationOptions = <String>[
  'Cek stok',
  'Cek pemasukan/pengeluaran',
  'Input draf transaksi',
  'Analisis laporan',
];

const Map<String, String> _seedMap = <String, String>{
  // Common abbreviations
  'gmn': 'gimana',
  'gmna': 'gimana',
  'brp': 'berapa',
  'bbrp': 'beberapa',
  'yg': 'yang',
  'sy': 'saya',
  'aq': 'aku',
  'gw': 'aku',
  'udh': 'sudah',
  'sdh': 'sudah',
  'blm': 'belum',
  'sm': 'sama',
  'dr': 'dari',
  'dgn': 'dengan',
  'krn': 'karena',
  'utk': 'untuk',
  'ttg': 'tentang',
  'pls': 'tolong',
  'plis': 'tolong',
  // Negation variants
  'ga': 'tidak',
  'gak': 'tidak',
  'ngga': 'tidak',
  'nggak': 'tidak',
  'tdk': 'tidak',
  'tak': 'tidak',
  'ora': 'tidak',
  'ra': 'tidak',
  // Finance/stock typo variants
  'stokk': 'stok',
  'stokkk': 'stok',
  'stoknyaa': 'stoknya',
  'pengeluran': 'pengeluaran',
  'pngeluaran': 'pengeluaran',
  'pemasukn': 'pemasukan',
  'pemasukann': 'pemasukan',
  'laporann': 'laporan',
  'analisa': 'analisis',
  // Regional words (seed)
  'piro': 'berapa',
  'piye': 'gimana',
  'ndak': 'tidak',
  'mboten': 'tidak',
};
