import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/deleted_transaction_model.dart';
import '../models/transaction_item_model.dart';
import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/export_service.dart';
import 'transaction_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'Semua';
  bool _isExporting = false;
  int _lastSeenEpoch = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<String> _filters = [
    'Hari Ini',
    'Kemarin',
    '7 Hari',
    'Bulan Ini',
    'Semua',
  ];

  @override
  void initState() {
    super.initState();
    Provider.of<TransactionProvider>(context, listen: false).loadTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _matchesFilter(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_filter) {
      case 'Hari Ini':
        return _isSameDate(date, today);
      case 'Kemarin':
        final yesterday = today.subtract(const Duration(days: 1));
        return _isSameDate(date, yesterday);
      case '7 Hari':
        final start = today.subtract(const Duration(days: 6));
        return !date.isBefore(start) && !date.isAfter(today);
      case 'Bulan Ini':
        return date.year == today.year && date.month == today.month;
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
              _searchController.clear();
              _searchQuery = '';
              _lastSeenEpoch = provider.restoreEpoch;
            });
          });
        }
        final baseFiltered = provider.transactions.where((tx) {
          if (tx.type == 'WASTE') {
            return false;
          }
          final date = DateTime.tryParse(tx.date);
          if (date == null) {
            return false;
          }
          return _matchesFilter(date);
        }).toList();
        final needsItemSearch = _searchQuery.trim().isNotEmpty;
        final txIds = needsItemSearch
            ? baseFiltered
                .map((tx) => tx.id)
                .whereType<int>()
                .toList()
            : const <int>[];
        final itemsFuture = needsItemSearch && txIds.isNotEmpty
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
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.file_download),
                onPressed: _isExporting
                    ? null
                    : () => _exportFiltered(context, provider),
                tooltip: 'Export Excel',
              ),
            ],
          ),
          body: Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        });
                      },
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: _filters.length,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    suffixIcon: _searchQuery.isEmpty
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
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
                          color: balance >= 0
                              ? const Color(0xFF1565C0)
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<Map<int, List<TransactionItemModel>>>(
                  future: itemsFuture,
                  builder: (context, snapshot) {
                    final itemsByTxId = snapshot.data ?? const {};
                    final deepFiltered = baseFiltered.where((tx) {
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

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    final searchActive = _searchQuery.trim().isNotEmpty;
                    final searchLabel =
                        "Ditemukan ${deepFiltered.length} transaksi dengan kata '${_searchQuery.trim()}'";

                    Widget listContent;
                    if (deepFiltered.isEmpty) {
                      final emptyLabel = searchActive
                          ? 'Transaksi tidak ditemukan'
                          : 'Belum ada transaksi';
                      listContent = Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(
                              emptyLabel,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    } else {
                      listContent = ListView.builder(
                        itemCount: deepFiltered.length,
                        itemBuilder: (context, index) {
                          final tx = deepFiltered[index];
                          final isIncome = tx.type == 'IN';
                          final color = isIncome ? Colors.green : Colors.red;
                          final icon = isIncome
                              ? Icons.arrow_downward
                              : Icons.arrow_upward;
                          final description = tx.description?.isNotEmpty == true
                              ? tx.description!
                              : null;
                          final dateLabel = DateFormat(
                            'd MMMM y HH:mm',
                            'id_ID',
                          ).format(DateTime.parse(tx.date));
                          final subtitleText = description == null
                              ? dateLabel
                              : '$dateLabel • $description';

                          final matchInfo = searchActive && tx.id != null
                              ? _buildMatchInfo(tx.id!, itemsByTxId)
                              : null;
                          final matchLabel = matchInfo == null
                              ? null
                              : 'Mengandung: ${matchInfo.name} '
                                  '(${matchInfo.quantity} pcs)'
                                  '${matchInfo.hasMore ? ' dan lainnya' : ''}';

                          return ListTile(
                            leading: Icon(icon, color: color),
                            title: Text(tx.categoryName ?? 'Transaksi'),
                            subtitle: matchLabel == null
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
                                  builder: (_) =>
                                      TransactionDetailScreen(transaction: tx),
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
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Hapus transaksi ini?'),
                                        content: const Text(
                                          'Data yang dihapus tidak bisa dikembalikan.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(false),
                                            child: const Text('Batal'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
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
                        },
                      );
                    }

                    return Column(
                      children: [
                        if (searchActive)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                searchLabel,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        Expanded(child: listContent),
                      ],
                    );
                  },
                ),
              ),
            ],
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mengekspor data...')),
    );

    try {
      await ExportService.exportTransactionsToExcel(
        filtered,
        filterLabel: _filterLabelForExport(),
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan berhasil dibuat')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengekspor laporan')),
      );
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
      case '7 Hari':
        final start = now.subtract(const Duration(days: 6));
        final startLabel = DateFormat('d MMM', 'id_ID').format(start);
        final endLabel = DateFormat('d MMM y', 'id_ID').format(now);
        return '$startLabel - $endLabel';
      case 'Bulan Ini':
        return DateFormat('MMMM y', 'id_ID').format(now);
      case 'Semua':
      default:
        return 'Semua Data';
    }
  }

  void _showAuditLog(
    BuildContext context,
    TransactionProvider provider,
  ) {
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
                          icon:
                              const Icon(Icons.delete_sweep, color: Colors.red),
                          onPressed: deleted.isEmpty
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
                          separatorBuilder: (_, __) => const Divider(height: 24),
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
                                      final restored =
                                          await provider.restoreDeletedTransaction(
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
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
