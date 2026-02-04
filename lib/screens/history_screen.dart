import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'Semua';

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

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat'),
      ),
      body: Consumer<TransactionProvider>(
        builder: (context, provider, _) {
          final filtered = provider.transactions.where((tx) {
            if (tx.type == 'WASTE') {
              return false;
            }
            final date = DateTime.tryParse(tx.date);
            if (date == null) {
              return false;
            }
            return _matchesFilter(date);
          }).toList();

          final totalIncome = filtered
              .where((tx) => tx.type == 'IN')
              .fold<int>(0, (sum, tx) => sum + tx.amount);
          final totalExpense = filtered
              .where((tx) => tx.type == 'OUT')
              .fold<int>(0, (sum, tx) => sum + tx.amount);
          final balance = totalIncome - totalExpense;

          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                child: filtered.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'Belum ada transaksi',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final tx = filtered[index];
                          final isIncome = tx.type == 'IN';
                          final color = isIncome ? Colors.green : Colors.red;
                          final icon =
                              isIncome ? Icons.arrow_downward : Icons.arrow_upward;
                          final description = tx.description?.isNotEmpty == true
                              ? tx.description!
                              : null;
                          final dateLabel = DateFormat('d MMMM y', 'id_ID')
                              .format(DateTime.parse(tx.date));
                          final subtitleText = description == null
                              ? dateLabel
                              : '$dateLabel • $description';

                          return ListTile(
                            leading: Icon(icon, color: color),
                            title: Text(tx.categoryName ?? 'Transaksi'),
                            subtitle: Text(subtitleText),
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
                                  icon: const Icon(Icons.delete, color: Colors.red),
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
                                        productProvider: Provider.of<ProductProvider>(
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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
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
