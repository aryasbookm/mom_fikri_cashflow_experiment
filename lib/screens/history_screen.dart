import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_item_model.dart';
import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/ai_quota_guard_service.dart';
import '../services/export_service.dart';
import 'ocr_assist_screen.dart';
import 'transaction_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'Semua';
  DateTime? _customDate;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  DateTime? _customMonth;
  int _customMonthYear = DateTime.now().year;
  bool _isExporting = false;
  int _lastSeenEpoch = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  AiQuotaGuardState _aiQuotaState = const AiQuotaGuardState(
    isBlocked: false,
    isDailyLimit: false,
    retryAfterSeconds: 0,
    message: '',
  );

  final List<String> _filters = [
    'Hari Ini',
    '7 Hari Terakhir',
    'Bulan Ini',
    'Semua',
  ];

  @override
  void initState() {
    super.initState();
    Provider.of<TransactionProvider>(context, listen: false).loadTransactions();
    _refreshAiQuotaState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _toDay(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isAdvancedFilterActive =>
      _filter == 'Tanggal' || _filter == 'Rentang' || _filter == 'Bulan Pilihan';

  Future<void> _pickCustomDate() async {
    final initial = _customDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal transaksi',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customDate = _toDay(picked);
      _filter = 'Tanggal';
      _customMonth = null;
    });
  }

  Future<void> _pickRangeStart() async {
    final initial = _rangeStart ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal awal',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _rangeStart = _toDay(picked);
      if (_rangeEnd != null && _rangeEnd!.isBefore(_rangeStart!)) {
        _rangeEnd = _rangeStart;
      }
      _filter = 'Rentang';
      _customMonth = null;
    });
  }

  Future<void> _pickRangeEnd() async {
    final initial = _rangeEnd ?? _rangeStart ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal akhir',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _rangeEnd = _toDay(picked);
      if (_rangeStart != null && _rangeEnd!.isBefore(_rangeStart!)) {
        _rangeStart = _rangeEnd;
      }
      _filter = 'Rentang';
      _customMonth = null;
    });
  }

  Future<void> _pickCustomMonth() async {
    int tempMonth = (_customMonth ?? DateTime.now()).month;
    int tempYear = _customMonthYear;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text('Pilih Bulan'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: tempMonth,
                      decoration: const InputDecoration(labelText: 'Bulan'),
                      items: List.generate(12, (index) {
                        final month = index + 1;
                        final label = DateFormat(
                          'MMMM',
                          'id_ID',
                        ).format(DateTime(2024, month, 1));
                        return DropdownMenuItem<int>(
                          value: month,
                          child: Text(label),
                        );
                      }),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setStateDialog(() => tempMonth = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: tempYear,
                      decoration: const InputDecoration(labelText: 'Tahun'),
                      items: List.generate(11, (index) {
                        final year = DateTime.now().year - 5 + index;
                        return DropdownMenuItem<int>(
                          value: year,
                          child: Text('$year'),
                        );
                      }),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setStateDialog(() => tempYear = value);
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Batal'),
                  ),
                  TextButton(
                    onPressed: () {
                      final monthStart = DateTime(tempYear, tempMonth, 1);
                      final monthEnd = DateTime(tempYear, tempMonth + 1, 0);
                      setState(() {
                        _customMonth = monthStart;
                        _customMonthYear = tempYear;
                        _rangeStart = monthStart;
                        _rangeEnd = monthEnd;
                        _filter = 'Bulan Pilihan';
                      });
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Terapkan'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _openAdvancedFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Tanggal tertentu'),
                  subtitle: const Text('Lihat transaksi 1 hari spesifik'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickCustomDate();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.date_range),
                  title: const Text('Rentang tanggal'),
                  subtitle: const Text('Atur tanggal awal dan akhir'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() {
                      _filter = 'Rentang';
                      _rangeStart ??= _toDay(DateTime.now());
                      _rangeEnd ??= _toDay(DateTime.now());
                      _customMonth = null;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: const Text('Pilih Bulan'),
                  subtitle: const Text('Pilih laporan 1 bulan penuh'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickCustomMonth();
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
    );
  }

  Widget _buildDateControlChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  Future<void> _refreshAiQuotaState() async {
    final state = await AiQuotaGuardService.getState();
    if (!mounted) {
      return;
    }
    setState(() {
      _aiQuotaState = state;
    });
  }

  bool _matchesFilter(DateTime date) {
    final now = DateTime.now();
    final today = _toDay(now);
    final target = _toDay(date);

    switch (_filter) {
      case 'Hari Ini':
        return _isSameDate(target, today);
      case 'Kemarin':
        final yesterday = today.subtract(const Duration(days: 1));
        return _isSameDate(target, yesterday);
      case '7 Hari Terakhir':
        final start = today.subtract(const Duration(days: 6));
        return !target.isBefore(start) && !target.isAfter(today);
      case 'Bulan Ini':
        return target.year == today.year && target.month == today.month;
      case 'Tanggal':
        final picked = _customDate ?? today;
        return _isSameDate(target, picked);
      case 'Rentang':
        final start = _rangeStart ?? today;
        final end = _rangeEnd ?? today;
        return !target.isBefore(start) && !target.isAfter(end);
      case 'Bulan Pilihan':
        final selected = _customMonth ?? today;
        return target.year == selected.year && target.month == selected.month;
      case 'Semua':
      default:
        return true;
    }
  }

  bool _matchesSearch(TransactionModel tx) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final category = (tx.categoryName ?? '').toLowerCase();
    final description = (tx.description ?? '').toLowerCase();
    final amountText = tx.amount.toString();
    final rawDate = tx.date.toLowerCase();
    return category.contains(query) ||
        description.contains(query) ||
        amountText.contains(query) ||
        rawDate.contains(query);
  }

  bool _matchesItemSearch(
    int transactionId,
    Map<int, List<TransactionItemModel>> itemsByTxId,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final items = itemsByTxId[transactionId] ?? const [];
    for (final item in items) {
      if (item.productName.toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  _MatchInfo? _buildMatchInfo(
    int transactionId,
    Map<int, List<TransactionItemModel>> itemsByTxId,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return null;
    }
    final items = itemsByTxId[transactionId] ?? const [];
    TransactionItemModel? firstMatch;
    int matchCount = 0;
    for (final item in items) {
      if (item.productName.toLowerCase().contains(query)) {
        matchCount += 1;
        firstMatch ??= item;
      }
    }
    if (firstMatch == null) {
      return null;
    }
    return _MatchInfo(
      name: firstMatch.productName,
      quantity: firstMatch.quantity,
      hasMore: matchCount > 1,
    );
  }

  String _buildTransactionTitle(
    TransactionModel tx,
    Map<int, List<TransactionItemModel>> itemsByTxId,
  ) {
    if (tx.type != 'IN' || tx.id == null) {
      return tx.categoryName ?? 'Transaksi';
    }

    final items = itemsByTxId[tx.id!] ?? const <TransactionItemModel>[];
    if (items.isEmpty) {
      return tx.categoryName ?? 'Transaksi';
    }
    if (items.length == 1) {
      return items.first.productName;
    }

    final firstName = items.first.productName;
    final extraCount = items.length - 1;
    return '$firstName +$extraCount item';
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        if (provider.restoreEpoch > _lastSeenEpoch) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _filter = 'Semua';
              _customDate = null;
              _rangeStart = null;
              _rangeEnd = null;
              _customMonth = null;
              _searchController.clear();
              _searchQuery = '';
              _lastSeenEpoch = provider.restoreEpoch;
            });
          });
        }
        final baseFiltered =
            provider.transactions.where((tx) {
              if (tx.type == 'WASTE') {
                return false;
              }
              final date = DateTime.tryParse(tx.date);
              if (date == null) {
                return false;
              }
              return _matchesFilter(date);
            }).toList();
        final txIds = baseFiltered.map((tx) => tx.id).whereType<int>().toList();
        final itemsFuture =
            txIds.isNotEmpty
                ? provider.getItemsByTransactionIds(txIds)
                : Future.value(<int, List<TransactionItemModel>>{});

        final totalIncome = baseFiltered
            .where((tx) => tx.type == 'IN')
            .fold<int>(0, (sum, tx) => sum + tx.amount);
        final totalExpense = baseFiltered
            .where((tx) => tx.type == 'OUT')
            .fold<int>(0, (sum, tx) => sum + tx.amount);
        final balance = totalIncome - totalExpense;

        final auth = context.watch<AuthProvider>();
        final isOwner = auth.currentUser?.role == 'owner';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Riwayat'),
            actions: [
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.restore_from_trash),
                  tooltip: 'Audit Log',
                  onPressed: () async {
                    await provider.loadDeletedTransactions();
                    if (!context.mounted) {
                      return;
                    }
                    _showAuditLog(context, provider);
                  },
                ),
              IconButton(
                icon:
                    _isExporting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.file_download),
                onPressed:
                    _isExporting
                        ? null
                        : () => _exportFiltered(context, provider),
                tooltip: 'Export Excel',
              ),
            ],
          ),
          body: FutureBuilder<Map<int, List<TransactionItemModel>>>(
            future: itemsFuture,
            builder: (context, snapshot) {
              final itemsByTxId = snapshot.data ?? const {};
              final deepFiltered =
                  baseFiltered.where((tx) {
                    if (_searchQuery.trim().isEmpty) {
                      return true;
                    }
                    final id = tx.id;
                    if (id == null) {
                      return _matchesSearch(tx);
                    }
                    return _matchesSearch(tx) ||
                        _matchesItemSearch(id, itemsByTxId);
                  }).toList();

              final searchActive = _searchQuery.trim().isNotEmpty;
              final searchLabel =
                  "Ditemukan ${deepFiltered.length} transaksi dengan kata '${_searchQuery.trim()}'";

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final label = _filters[index];
                          final isSelected = label == _filter;
                          return ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() {
                                _filter = label;
                                if (label == 'Tanggal' && _customDate == null) {
                                  _customDate = _toDay(DateTime.now());
                                }
                                if (label != 'Tanggal') {
                                  _customMonth = null;
                                }
                              });
                            },
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: _filters.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _openAdvancedFilterSheet,
                            icon: const Icon(Icons.tune, size: 16),
                            label: const Text('Filter Lanjutan'),
                          ),
                          if (_isAdvancedFilterActive) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _filter == 'Tanggal'
                                    ? 'Aktif: Tanggal tertentu'
                                    : _filter == 'Rentang'
                                    ? 'Aktif: Rentang tanggal'
                                    : 'Aktif: Bulan pilihan',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Cari transaksi...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon:
                              _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  if (_filter == 'Tanggal' ||
                      _filter == 'Rentang' ||
                      _filter == 'Bulan Pilihan')
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_filter == 'Tanggal')
                              _buildDateControlChip(
                                label:
                                    'Tanggal: ${DateFormat('d MMM y', 'id_ID').format(_customDate ?? DateTime.now())}',
                                onTap: _pickCustomDate,
                              ),
                            if (_filter == 'Rentang') ...[
                              _buildDateControlChip(
                                label:
                                    'Dari: ${DateFormat('d MMM y', 'id_ID').format(_rangeStart ?? DateTime.now())}',
                                onTap: _pickRangeStart,
                              ),
                              _buildDateControlChip(
                                label:
                                    'Sampai: ${DateFormat('d MMM y', 'id_ID').format(_rangeEnd ?? DateTime.now())}',
                                onTap: _pickRangeEnd,
                              ),
                            ],
                            if (_filter == 'Bulan Pilihan')
                              _buildDateControlChip(
                                label:
                                    'Bulan: ${DateFormat('MMMM y', 'id_ID').format(_customMonth ?? DateTime.now())}',
                                onTap: _pickCustomMonth,
                              ),
                          ],
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.menu_book_outlined,
                              color: Color(0xFF8D1B3D),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Migrasi dari Buku',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _aiQuotaState.isBlocked
                                        ? _aiQuotaState.message
                                        : 'AI siap dipakai',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          _aiQuotaState.isBlocked
                                              ? const Color(0xFFC62828)
                                              : const Color(0xFF2E7D32),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed:
                                  _aiQuotaState.isBlocked
                                      ? null
                                      : () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const OcrAssistScreen(),
                                          ),
                                        );
                                        await _refreshAiQuotaState();
                                      },
                              icon: const Icon(
                                Icons.document_scanner_outlined,
                                size: 16,
                              ),
                              label: const Text('Scan'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _SummaryItem(
                                label: 'Masuk',
                                value: currency.format(totalIncome),
                                color: Colors.green,
                              ),
                            ),
                            Expanded(
                              child: _SummaryItem(
                                label: 'Keluar',
                                value: currency.format(totalExpense),
                                color: Colors.red,
                              ),
                            ),
                            Expanded(
                              child: _SummaryItem(
                                label: 'Saldo',
                                value: currency.format(balance),
                                color:
                                    balance >= 0
                                        ? const Color(0xFF1565C0)
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (searchActive)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Text(
                          searchLabel,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (deepFiltered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.history,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              searchActive
                                  ? 'Transaksi tidak ditemukan'
                                  : 'Belum ada transaksi',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final tx = deepFiltered[index];
                        final isIncome = tx.type == 'IN';
                        final color = isIncome ? Colors.green : Colors.red;
                        final icon =
                            isIncome ? Icons.arrow_downward : Icons.arrow_upward;
                        final description =
                            tx.description?.isNotEmpty == true
                                ? tx.description!
                                : null;
                        final dateLabel = DateFormat(
                          'd MMMM y HH:mm',
                          'id_ID',
                        ).format(DateTime.parse(tx.date));
                        final subtitleText =
                            description == null
                                ? dateLabel
                                : '$dateLabel • $description';

                        final matchInfo =
                            searchActive && tx.id != null
                                ? _buildMatchInfo(tx.id!, itemsByTxId)
                                : null;
                        final matchLabel =
                            matchInfo == null
                                ? null
                                : 'Mengandung: ${matchInfo.name} '
                                    '(${matchInfo.quantity} pcs)'
                                    '${matchInfo.hasMore ? ' dan lainnya' : ''}';

                        return ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(_buildTransactionTitle(tx, itemsByTxId)),
                          subtitle:
                              matchLabel == null
                                  ? Text(subtitleText)
                                  : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(subtitleText),
                                      const SizedBox(height: 4),
                                      Text(
                                        matchLabel,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => TransactionDetailScreen(
                                      transaction: tx,
                                    ),
                              ),
                            );
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currency.format(tx.amount),
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: const Text(
                                            'Hapus transaksi ini?',
                                          ),
                                          content: const Text(
                                            'Data yang dihapus tidak bisa dikembalikan.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.of(
                                                    context,
                                                  ).pop(false),
                                              child: const Text('Batal'),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.of(
                                                    context,
                                                  ).pop(true),
                                              child: const Text('Hapus'),
                                            ),
                                          ],
                                        ),
                                  );

                                  if (confirmed == true && tx.id != null) {
                                    await Provider.of<TransactionProvider>(
                                      context,
                                      listen: false,
                                    ).deleteTransaction(
                                      tx.id!,
                                      productProvider:
                                          Provider.of<ProductProvider>(
                                            context,
                                            listen: false,
                                          ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      }, childCount: deepFiltered.length),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<TransactionModel> _filteredForExport(TransactionProvider provider) {
    return provider.transactions.where((tx) {
      if (tx.type == 'WASTE') {
        return false;
      }
      final date = DateTime.tryParse(tx.date);
      if (date == null) {
        return false;
      }
      return _matchesFilter(date);
    }).toList();
  }

  Future<void> _exportFiltered(
    BuildContext context,
    TransactionProvider provider,
  ) async {
    if (_isExporting) {
      return;
    }
    final filtered = _filteredForExport(provider);
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada transaksi untuk diekspor')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mengekspor data...')));

    try {
      await ExportService.exportTransactionsToExcel(
        filtered,
        filterLabel: _filterLabelForExport(),
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Laporan berhasil dibuat')));
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gagal mengekspor laporan')));
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  String _filterLabelForExport() {
    final now = DateTime.now();
    switch (_filter) {
      case 'Hari Ini':
        return DateFormat('d MMMM y', 'id_ID').format(now);
      case 'Kemarin':
        final yesterday = now.subtract(const Duration(days: 1));
        return DateFormat('d MMMM y', 'id_ID').format(yesterday);
      case '7 Hari Terakhir':
        final start = now.subtract(const Duration(days: 6));
        final startLabel = DateFormat('d MMM', 'id_ID').format(start);
        final endLabel = DateFormat('d MMM y', 'id_ID').format(now);
        return '$startLabel - $endLabel';
      case 'Bulan Ini':
        return DateFormat('MMMM y', 'id_ID').format(now);
      case 'Tanggal':
        final d = _customDate ?? now;
        return DateFormat('d MMMM y', 'id_ID').format(d);
      case 'Rentang':
        final start = _rangeStart ?? now;
        final end = _rangeEnd ?? now;
        final startLabel = DateFormat('d MMM y', 'id_ID').format(start);
        final endLabel = DateFormat('d MMM y', 'id_ID').format(end);
        return '$startLabel - $endLabel';
      case 'Bulan Pilihan':
        final m = _customMonth ?? now;
        return DateFormat('MMMM y', 'id_ID').format(m);
      case 'Semua':
      default:
        return 'Semua Data';
    }
  }

  void _showAuditLog(BuildContext context, TransactionProvider provider) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Consumer<TransactionProvider>(
              builder: (context, provider, _) {
                final deleted = provider.deletedTransactions;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Audit Log Penghapusan',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kosongkan Audit Log',
                          icon: const Icon(
                            Icons.delete_sweep,
                            color: Colors.red,
                          ),
                          onPressed:
                              deleted.isEmpty
                                  ? null
                                  : () async {
                                    final confirm = await _confirmAction(
                                      context,
                                      title: 'Kosongkan Audit Log?',
                                      message:
                                          'Semua data audit akan dihapus permanen.',
                                      confirmLabel: 'Hapus Semua',
                                    );
                                    if (confirm != true) {
                                      return;
                                    }
                                    await provider.clearAllAuditLogs();
                                    if (!context.mounted) {
                                      return;
                                    }
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Audit log dikosongkan'),
                                      ),
                                    );
                                  },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (deleted.isEmpty)
                      const Text(
                        'Belum ada transaksi yang dihapus.',
                        style: TextStyle(color: Colors.grey),
                      )
                    else
                      SizedBox(
                        height: 400,
                        child: ListView.separated(
                          itemCount: deleted.length,
                          separatorBuilder:
                              (_, __) => const Divider(height: 24),
                          itemBuilder: (context, index) {
                            final item = deleted[index];
                            final dateLabel = DateFormat(
                              'd MMMM y, HH:mm',
                              'id_ID',
                            ).format(DateTime.parse(item.deletedAt));
                            final nominal = NumberFormat.currency(
                              locale: 'id_ID',
                              symbol: 'Rp ',
                            ).format(item.amount);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${item.type} • $nominal',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${item.category ?? 'Tanpa kategori'}\n'
                                'Dihapus oleh: ${item.deletedBy}\n'
                                'Waktu: $dateLabel\n'
                                'Alasan: ${item.reason}',
                              ),
                              isThreeLine: true,
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.restore),
                                    tooltip: 'Kembalikan transaksi',
                                    onPressed: () async {
                                      final confirm = await _confirmAction(
                                        context,
                                        title: 'Kembalikan Transaksi?',
                                        message:
                                            'Transaksi akan dimasukkan kembali ke riwayat.',
                                        confirmLabel: 'Kembalikan',
                                      );
                                      if (confirm != true) {
                                        return;
                                      }
                                      final productProvider =
                                          context.read<ProductProvider>();
                                      final restored = await provider
                                          .restoreDeletedTransaction(
                                            item,
                                            productProvider: productProvider,
                                          );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            restored
                                                ? 'Transaksi dikembalikan'
                                                : 'Gagal mengembalikan transaksi',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever),
                                    color: Colors.red,
                                    tooltip: 'Hapus permanen',
                                    onPressed: () async {
                                      final confirm = await _confirmAction(
                                        context,
                                        title: 'Hapus Permanen?',
                                        message:
                                            'Data audit ini akan hilang selamanya.',
                                        confirmLabel: 'Hapus',
                                      );
                                      if (confirm != true) {
                                        return;
                                      }
                                      final id = item.id;
                                      if (id == null) {
                                        return;
                                      }
                                      await provider.deleteAuditLog(id);
                                      if (!context.mounted) {
                                        return;
                                      }
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Audit log dihapus'),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }
}

class _MatchInfo {
  const _MatchInfo({
    required this.name,
    required this.quantity,
    required this.hasMore,
  });

  final String name;
  final int quantity;
  final bool hasMore;
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
