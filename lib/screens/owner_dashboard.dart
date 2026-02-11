import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product_model.dart';
import '../providers/product_provider.dart';
import '../providers/production_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/backup_service.dart';
import 'add_transaction_screen.dart';
import 'history_screen.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  static const String _targetKey = 'daily_target_amount';
  static const String _celebratedDateKey = 'daily_target_celebrated_date';
  static const String _showStockAlertKey = 'show_stock_alert';
  int _dailyTarget = 0;
  bool _isLoadingTarget = true;
  bool _showStockAlert = true;
  bool _showBackupAlert = false;
  bool _isBackingUp = false;
  late final ConfettiController _confettiController;
  Future<List<Map<String, dynamic>>>? _topProductsFuture;
  Future<List<Map<String, dynamic>>>? _slowMovingFuture;
  int _lastTxCount = -1;
  int _lastSlowTxCount = -1;
  int _lastSlowProductCount = -1;

  @override
  void initState() {
    super.initState();
    Provider.of<TransactionProvider>(context, listen: false).loadTransactions();
    Provider.of<ProductProvider>(context, listen: false).loadProducts();
    Provider.of<ProductionProvider>(context, listen: false).loadTodayProduction();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
    _loadDailyTarget();
    _loadBackupReminder();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadDailyTarget() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _dailyTarget = prefs.getInt(_targetKey) ?? 0;
      _showStockAlert = prefs.getBool(_showStockAlertKey) ?? true;
      _isLoadingTarget = false;
    });
  }

  Future<void> _loadBackupReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackup = prefs.getInt(BackupService.lastBackupKey);
    final lastDataCount = prefs.getInt(BackupService.lastBackupDataCountKey);
    final currentCount = await BackupService.getCurrentDataCount();
    final now = DateTime.now();
    final hasChanges = lastDataCount == null
        ? currentCount > 0
        : currentCount != lastDataCount;
    final isOverdue = hasChanges &&
        (lastBackup == null ||
            now.difference(DateTime.fromMillisecondsSinceEpoch(lastBackup)) >
                const Duration(days: 3));
    if (!mounted) {
      return;
    }
    setState(() {
      _showBackupAlert = isOverdue;
    });
  }

  Future<void> _backupDatabase() async {
    if (_isBackingUp) {
      return;
    }
    setState(() {
      _isBackingUp = true;
    });
    try {
      final result = await BackupService.backupDatabase(shareAfter: true);
      if (!mounted) {
        return;
      }
      final downloadMessage = result.downloadPath != null
          ? 'Backup tersimpan di: ${result.downloadPath}'
          : 'Backup selesai, tetapi gagal simpan ke folder Download.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(downloadMessage)),
      );
      setState(() {
        _showBackupAlert = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat backup: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
        });
      }
    }
  }

  Future<void> _setShowStockAlert(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showStockAlertKey, value);
    if (!mounted) {
      return;
    }
    setState(() {
      _showStockAlert = value;
    });
  }

  Future<void> _setDailyTarget(int target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_targetKey, target);
    if (!mounted) {
      return;
    }
    setState(() {
      _dailyTarget = target;
    });
  }

  Future<void> _clearDailyTarget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_targetKey, 0);
    await prefs.remove(_celebratedDateKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _dailyTarget = 0;
    });
  }

  Future<int?> _showTargetDialog({required int initialValue}) async {
    final controller =
        TextEditingController(text: initialValue > 0 ? '$initialValue' : '');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pasang Target Hari Ini'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Target Omzet (Rp)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(value);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _maybeCelebrate({
    required int todayIncome,
    required String todayKey,
  }) async {
    if (_dailyTarget <= 0 || todayIncome < _dailyTarget) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final lastCelebrated = prefs.getString(_celebratedDateKey);
    if (lastCelebrated == todayKey) {
      return;
    }
    await prefs.setString(_celebratedDateKey, todayKey);
    if (!mounted) {
      return;
    }
    _confettiController.play();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Consumer3<TransactionProvider, ProductProvider, ProductionProvider>(
      builder: (context, provider, productProvider, productionProvider, _) {
        final txCount = provider.transactions.length;
        final productCount = productProvider.products.length;
        if (_topProductsFuture == null || _lastTxCount != txCount) {
          _lastTxCount = txCount;
          _topProductsFuture = provider.getTopProductsLast7Days(limit: 5);
        }
        if (_slowMovingFuture == null ||
            _lastSlowTxCount != txCount ||
            _lastSlowProductCount != productCount) {
          _lastSlowTxCount = txCount;
          _lastSlowProductCount = productCount;
          _slowMovingFuture = provider.getSlowMovingProducts(
            limit: 5,
            days: 30,
          );
        }
        final todayDate = DateTime.now();
        final todayTx = provider.transactions.where((tx) {
          final parsed = DateTime.tryParse(tx.date);
          if (parsed == null) {
            return false;
          }
          final sameDay = parsed.year == todayDate.year &&
              parsed.month == todayDate.month &&
              parsed.day == todayDate.day;
          return sameDay && tx.type != 'WASTE';
        }).toList();
        final todayIncome = todayTx
            .where((tx) => tx.type == 'IN')
            .fold<int>(0, (sum, tx) => sum + tx.amount);
        final todayExpense = todayTx
            .where((tx) => tx.type == 'OUT')
            .fold<int>(0, (sum, tx) => sum + tx.amount);
        final hasOperationalData =
            provider.transactions.isNotEmpty ||
            productionProvider.todayItems.isNotEmpty ||
            productProvider.products.any((product) => product.stock > 0);
        final totalStock = productProvider.products
            .fold<int>(0, (sum, product) => sum + product.stock);
        final lowStock = productProvider.products
            .where((product) => product.isActive)
            .where((product) => product.stock <= product.minStock)
            .toList();

        final todayKey =
            DateFormat('yyyy-MM-dd').format(DateTime.now());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeCelebrate(todayIncome: todayIncome, todayKey: todayKey);
        });

        return Stack(
          alignment: Alignment.topCenter,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showBackupAlert && hasOperationalData)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFE8A1)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.warning_amber_rounded,
                                color: Color(0xFF8D1B3D)),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Backup data belum dilakukan > 3 hari. '
                              'Disarankan backup sekarang.',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              TextButton(
                                onPressed: _isBackingUp ? null : _backupDatabase,
                                child: _isBackingUp
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Backup'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _showBackupAlert = false;
                                  });
                                },
                                tooltip: 'Tutup',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (_showBackupAlert && hasOperationalData)
                    const SizedBox(height: 12),
                  if (_isLoadingTarget)
                    const SizedBox(height: 12)
                  else if (_dailyTarget <= 0)
                    _TargetPrompt(
                      onTap: () async {
                        final value = await _showTargetDialog(initialValue: 0);
                        if (value != null && value > 0) {
                          await _setDailyTarget(value);
                        }
                      },
                    )
                  else
                    _TargetProgressCard(
                      target: _dailyTarget,
                      achieved: todayIncome,
                      currency: currency,
                      onEdit: () async {
                        final value = await _showTargetDialog(
                          initialValue: _dailyTarget,
                        );
                        if (value != null && value > 0) {
                          await _setDailyTarget(value);
                        }
                      },
                      onClear: _clearDailyTarget,
                    ),
                  const SizedBox(height: 8),
                  if (hasOperationalData) ...[
                    _StockAlertToggle(
                      value: _showStockAlert,
                      onChanged: _setShowStockAlert,
                    ),
                    if (lowStock.isNotEmpty && _showStockAlert) ...[
                      const SizedBox(height: 12),
                      _LowStockCard(products: lowStock),
                    ],
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Laporan Keuangan Anda',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FinanceCard(
                    balance: currency.format(provider.balance),
                    income: currency.format(provider.totalIncome),
                    expense: currency.format(provider.totalExpense),
                  ),
                  const SizedBox(height: 16),
                  _StatCard(
                    backgroundColor: const Color(0xFF8D1B3D),
                    title: 'Total Stok Tersedia',
                    value: '$totalStock Pcs',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.attach_money,
                          title: 'Catat Pemasukan',
                          color: Colors.green,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AddTransactionScreen(
                                    initialType: 'IN'),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.shopping_basket,
                          title: 'Catat Pengeluaran',
                          color: Colors.orange,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AddTransactionScreen(
                                    initialType: 'OUT'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ActionCard(
                    icon: Icons.history,
                    title: 'Riwayat Transaksi',
                    color: const Color(0xFF1565C0),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HistoryScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ringkasan Hari Ini',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SummaryRow(
                          icon: Icons.savings,
                          label: 'Pemasukan',
                          value: currency.format(todayIncome),
                          color: Colors.green,
                        ),
                        const SizedBox(height: 8),
                        _SummaryRow(
                          icon: Icons.payments_outlined,
                          label: 'Pengeluaran',
                          value: currency.format(todayExpense),
                          color: Colors.red,
                        ),
                        const SizedBox(height: 8),
                        _SummaryRow(
                          icon: Icons.cake_outlined,
                          label: 'Kue Diproduksi',
                          value: '${productionProvider.totalQuantityToday} Pcs',
                          color: const Color(0xFF8D1B3D),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _TopProductsCard(
                    future: _topProductsFuture,
                  ),
                  const SizedBox(height: 16),
                  _SlowMovingCard(
                    future: _slowMovingFuture,
                  ),
                ],
              ),
            ),
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 20,
              gravity: 0.2,
              emissionFrequency: 0.04,
            ),
          ],
        );
      },
    );
  }
}

class _TargetPrompt extends StatelessWidget {
  const _TargetPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF8D1B3D)),
        ),
        child: Row(
          children: const [
            Icon(Icons.flag, color: Color(0xFF8D1B3D)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pasang Target Hari Ini',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8D1B3D),
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Color(0xFF8D1B3D)),
          ],
        ),
      ),
    );
  }
}

class _TargetProgressCard extends StatelessWidget {
  const _TargetProgressCard({
    required this.target,
    required this.achieved,
    required this.currency,
    required this.onEdit,
    required this.onClear,
  });

  final int target;
  final int achieved;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final percent = target <= 0
        ? 0.0
        : (achieved / target).clamp(0.0, 1.0);
    final progressColor = percent >= 1
        ? Colors.green
        : percent >= 0.7
            ? Colors.orange
            : Colors.red;

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Target Hari Ini',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Edit Target',
              ),
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Nonaktifkan',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${currency.format(achieved)} dari ${currency.format(target)}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          LinearPercentIndicator(
            lineHeight: 10,
            percent: percent,
            backgroundColor: Colors.grey.shade200,
            progressColor: progressColor,
            barRadius: const Radius.circular(8),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _StockAlertToggle extends StatelessWidget {
  const _StockAlertToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active,
              color: Color(0xFF8D1B3D), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Peringatan Stok',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF8D1B3D),
          ),
        ],
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.products});

  final List<ProductModel> products;

  @override
  Widget build(BuildContext context) {
    final visible = products.take(3).toList();
    final remaining = products.length - visible.length;
    final names = visible.map((p) => p.name).join(', ');
    final summary = remaining > 0 ? '$names, +$remaining lainnya' : names;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.orange.withOpacity(0.2),
            child: const Icon(Icons.warning_amber, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stok Menipis (${products.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: const TextStyle(color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.backgroundColor,
    required this.title,
    required this.value,
    this.valueSize = 20,
  });

  final Color backgroundColor;
  final String title;
  final String value;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: valueSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
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

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.future});

  final Future<List<Map<String, dynamic>>>? future;

  @override
  Widget build(BuildContext context) {
    return _DashboardExpansionCard(
      title: 'Produk Terlaris (7 Hari)',
      initiallyExpanded: true,
      child: future == null
          ? const Text('Belum ada data')
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (items.isEmpty) {
                  return const Text('Belum ada transaksi 7 hari terakhir');
                }
                return Column(
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == items.length - 1 ? 0 : 8,
                        ),
                        child: _TopProductRow(
                          rank: i + 1,
                          name: items[i]['name']?.toString() ?? '-',
                          quantity:
                              (items[i]['total_qty'] as num?)?.toInt() ?? 0,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({
    required this.rank,
    required this.name,
    required this.quantity,
  });

  final int rank;
  final String name;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF8D1B3D).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$rank',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF8D1B3D),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$quantity pcs',
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}

class _SlowMovingCard extends StatelessWidget {
  const _SlowMovingCard({required this.future});

  final Future<List<Map<String, dynamic>>>? future;

  @override
  Widget build(BuildContext context) {
    return _DashboardExpansionCard(
      title: 'Produk Kurang Laris (30 Hari)',
      initiallyExpanded: true,
      child: future == null
          ? const Text('Belum ada data')
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (items.isEmpty) {
                  return const Text('Belum ada produk aktif');
                }
                return Column(
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == items.length - 1 ? 0 : 8,
                        ),
                        child: _SlowMovingRow(
                          name: items[i]['name']?.toString() ?? '-',
                          sold:
                              (items[i]['total_qty'] as num?)?.toInt() ?? 0,
                          stock: (items[i]['stock'] as num?)?.toInt() ?? 0,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _SlowMovingRow extends StatelessWidget {
  const _SlowMovingRow({
    required this.name,
    required this.sold,
    required this.stock,
  });

  final String name;
  final int sold;
  final int stock;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.trending_down, size: 16, color: Colors.orange),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          'Terjual $sold • Stok $stock',
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}

class _DashboardExpansionCard extends StatelessWidget {
  const _DashboardExpansionCard({
    required this.title,
    required this.child,
    required this.initiallyExpanded,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          initiallyExpanded: initiallyExpanded,
          children: [child],
        ),
      ),
    );
  }
}

class _FinanceCard extends StatelessWidget {
  const _FinanceCard({
    required this.balance,
    required this.income,
    required this.expense,
  });

  final String balance;
  final String income;
  final String expense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saldo Saat Ini',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            balance,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _FinanceMini(
                  label: 'Pemasukan',
                  value: income,
                  color: Colors.green,
                  icon: Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FinanceMini(
                  label: 'Pengeluaran',
                  value: expense,
                  color: Colors.orange,
                  icon: Icons.arrow_upward,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinanceMini extends StatelessWidget {
  const _FinanceMini({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withOpacity(0.2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
