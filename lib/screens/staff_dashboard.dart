import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import 'add_transaction_screen.dart';
import 'production_screen.dart';
import 'login_screen.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  int _currentIndex = 0;
  int? _userId;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _userId = authProvider.currentUser?.id;
    if (_userId != null) {
      Provider.of<TransactionProvider>(context, listen: false)
          .loadTodayTransactionsForUser(_userId!);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi Keluar'),
          content: const Text('Apakah Anda yakin ingin keluar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Keluar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    authProvider.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');

    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final totalSetoran = provider.transactions.fold<int>(
          0,
          (sum, item) => item.type == 'IN' ? sum + item.amount : sum - item.amount,
        );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
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
                      'Total Setoran Hari Ini',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currency.format(totalSetoran),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: provider.transactions.isEmpty
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
                      itemCount: provider.transactions.length,
                      itemBuilder: (context, index) {
                        final tx = provider.transactions[index];
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
                                      if (_userId != null && mounted) {
                                        Provider.of<TransactionProvider>(
                                        context,
                                        listen: false,
                                      ).loadTodayTransactionsForUser(_userId!);
                                    }
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
    );
  }

  Widget _buildAccount(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_circle, size: 100, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            user?.username ?? 'Karyawan',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            user?.role ?? 'staff',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            onPressed: () => _confirmLogout(context),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHome(context),
      const ProductionScreen(showAppBar: false),
      _buildAccount(context),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? 'Dashboard Staff'
              : _currentIndex == 1
                  ? 'Stok'
                  : 'Akun',
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AddTransactionScreen(),
                  ),
                );
                if (_userId != null && mounted) {
                  Provider.of<TransactionProvider>(context, listen: false)
                      .loadTodayTransactionsForUser(_userId!);
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF8D1B3D),
        backgroundColor: Colors.white,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'Stok',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Akun',
          ),
        ],
      ),
    );
  }
}
