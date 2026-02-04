import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/production_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import '../providers/production_provider.dart';
import '../providers/transaction_provider.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  String? _selectedProductName;
  int? _selectedProductId;
  final TextEditingController _quantityController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Provider.of<ProductProvider>(context, listen: false).loadProducts();
    Provider.of<ProductionProvider>(context, listen: false).loadTodayProduction();
    Provider.of<CategoryProvider>(context, listen: false).loadCategories();
    Provider.of<TransactionProvider>(context, listen: false).loadTransactions();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _addProduct() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tambah Produk Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Produk',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Harga',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    if (result != true) {
      return;
    }

    final name = nameController.text.trim();
    final price = int.tryParse(priceController.text.trim()) ?? 0;
    if (name.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan harga wajib diisi.')),
      );
      return;
    }

    await context.read<ProductProvider>().addProduct(name, price);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Produk baru ditambahkan.')),
    );
  }

  Future<void> _saveProduction() async {
    if (_isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    final quantity = int.tryParse(_quantityController.text.trim());

    if (_selectedProductId == null ||
        _selectedProductName == null ||
        quantity == null ||
        quantity <= 0) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi data produksi.')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;

    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User belum login.')),
      );
      return;
    }

    final item = ProductionModel(
      productName: _selectedProductName!,
      quantity: quantity,
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      userId: userId,
    );

    final updated = await context
        .read<ProductProvider>()
        .updateStock(_selectedProductId!, quantity);
    if (!updated) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menambah stok.')),
      );
      return;
    }

    await context.read<ProductionProvider>().addProduction(item);

    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });
    _quantityController.clear();
  }

  Future<void> _wasteStock(int productId, String productName) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Buang $productName'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Jumlah',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Buang'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final qty = int.tryParse(controller.text.trim()) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jumlah tidak valid.')),
      );
      return;
    }

    final updated =
        await context.read<ProductProvider>().updateStock(productId, -qty);
    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok tidak cukup.')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User belum login.')),
      );
      return;
    }

    final categoryProvider = context.read<CategoryProvider>();
    final wasteCategoryId = _resolveWasteCategory(categoryProvider);
    if (wasteCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori pengeluaran belum tersedia.')),
      );
      return;
    }

    await context.read<TransactionProvider>().addWasteTransaction(
          productId: productId,
          quantity: qty,
          userId: userId,
          categoryId: wasteCategoryId,
          description: 'Buang $productName ($qty pcs)',
          date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        );

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stok dikurangi.')),
    );
  }

  int? _resolveWasteCategory(CategoryProvider categoryProvider) {
    final expense = categoryProvider.expenseCategories;
    for (final cat in expense) {
      if (cat.name.toLowerCase().trim() == 'operasional') {
        return cat.id;
      }
    }
    if (expense.isNotEmpty) {
      return expense.first.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Produksi Kue'),
            )
          : null,
      body: Consumer3<ProductionProvider, ProductProvider, TransactionProvider>(
        builder: (context, productionProvider, productProvider, transactionProvider, _) {
          final products = productProvider.products;
          if (_selectedProductName == null && products.isNotEmpty) {
            _selectedProductName = products.first.name;
            _selectedProductId = products.first.id;
          }
          final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
          final wasteToday = transactionProvider.transactions.where((tx) {
            return tx.type == 'WASTE' && tx.date == today;
          }).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8D1B3D),
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
                        'Total Produksi Hari Ini',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${productionProvider.totalQuantityToday} Pcs',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
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
                        'Total Produksi Keseluruhan',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${productionProvider.totalQuantityAll} Pcs',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
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
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedProductName,
                              decoration: const InputDecoration(
                                labelText: 'Nama Kue',
                                border: OutlineInputBorder(),
                              ),
                              items: products
                                  .map(
                                    (product) => DropdownMenuItem<String>(
                                      value: product.name,
                                      child: Text(product.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedProductName = value;
                                  _selectedProductId = products
                                      .firstWhere((p) => p.name == value)
                                      .id;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _addProduct,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Jumlah',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveProduction,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Catat'),
                        ),
                      ),
                    ],
                  ),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Stok Produk',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...products.map((product) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(product.name),
                          subtitle: Text('Stok: ${product.stock}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () {
                              if (product.id != null) {
                                _wasteStock(product.id!, product.name);
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (productionProvider.todayItems.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Belum ada produksi hari ini',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Daftar Produksi Hari Ini',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...productionProvider.todayItems.map((item) {
                          final product = products
                              .where((p) => p.name == item.productName)
                              .toList();
                          final stock = product.isNotEmpty ? product.first.stock : 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.productName),
                            subtitle: Text('Stok saat ini: $stock'),
                            trailing: Text('${item.quantity} pcs'),
                          );
                        }).toList(),
                      ],
                    ),
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Barang Rusak/Basi Hari Ini',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (wasteToday.isEmpty)
                        const Text(
                          'Belum ada barang rusak hari ini',
                          style: TextStyle(color: Colors.grey),
                        )
                      else
                        ...wasteToday.map((item) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.description ?? 'Barang rusak'),
                            trailing: Text('${item.quantity ?? 0} pcs'),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
