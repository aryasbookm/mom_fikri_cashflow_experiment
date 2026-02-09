import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../models/transaction_item_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key, this.initialType});

  final String? initialType;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _customCategoryController =
      TextEditingController();

  String _type = 'IN';
  int? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  bool _manualIncomeInput = false;
  bool _isLoading = false;
  final List<_CartItem> _cartItems = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) {
      _type = widget.initialType!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      Provider.of<CategoryProvider>(context, listen: false)
          .setCurrentRole(authProvider.currentUser?.role);
      Provider.of<CategoryProvider>(context, listen: false).loadCategories();
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  Future<int?> _showQuantityDialog() async {
    FocusScope.of(context).unfocus();
    final controller = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Masukkan Jumlah'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Contoh: 5'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                final qty = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(qty);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _resetProductSelection() {
    _cartItems.clear();
    _amountController.clear();
    _descriptionController.clear();
  }

  int _cartTotal() {
    return _cartItems.fold<int>(
      0,
      (sum, item) => sum + (item.price * item.quantity),
    );
  }

  Future<void> _addToCart({
    required int productId,
    required String name,
    required int price,
    required int stock,
  }) async {
    final qty = await _showQuantityDialog();
    if (!mounted) {
      return;
    }
    if (qty == null || qty <= 0) {
      return;
    }
    final existingIndex =
        _cartItems.indexWhere((item) => item.productId == productId);
    if (existingIndex != -1) {
      final currentQty = _cartItems[existingIndex].quantity;
      final nextQty = currentQty + qty;
      if (nextQty > stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stok tidak cukup! Sisa: $stock')),
        );
        return;
      }
      setState(() {
        _cartItems[existingIndex] =
            _cartItems[existingIndex].copyWith(quantity: nextQty);
      });
    } else {
      if (qty > stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stok tidak cukup! Sisa: $stock')),
        );
        return;
      }
      setState(() {
        _cartItems.add(
          _CartItem(
            productId: productId,
            name: name,
            price: price,
            quantity: qty,
          ),
        );
      });
    }
    _amountController.text = _cartTotal().toString();
    _descriptionController.text =
        'Penjualan ${_cartItems.length} item';
  }

  Future<void> _editCartItem(_CartItem item, int stock) async {
    final controller = TextEditingController(text: '${item.quantity}');
    final newQty = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Ubah jumlah ${item.name}'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Contoh: 5'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                final qty = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(qty);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
    if (newQty == null || newQty <= 0) {
      return;
    }
    if (newQty > stock) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stok tidak cukup! Sisa: $stock')),
      );
      return;
    }
    setState(() {
      final index =
          _cartItems.indexWhere((entry) => entry.productId == item.productId);
      if (index != -1) {
        _cartItems[index] = _cartItems[index].copyWith(quantity: newQty);
      }
      _amountController.text = _cartTotal().toString();
      _descriptionController.text =
          'Penjualan ${_cartItems.length} item';
    });
  }

  void _removeCartItem(_CartItem item) {
    setState(() {
      _cartItems.removeWhere((entry) => entry.productId == item.productId);
      _amountController.text =
          _cartItems.isEmpty ? '' : _cartTotal().toString();
      _descriptionController.text =
          _cartItems.isEmpty ? '' : 'Penjualan ${_cartItems.length} item';
    });
  }

  Future<void> _saveTransaction() async {
    if (_isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
    });

    final amountText = _amountController.text.trim();
    final amount = int.tryParse(amountText);

    if (amount == null || amount <= 0 || _selectedCategoryId == null) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi data transaksi.')),
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

    int categoryId = _selectedCategoryId!;
    final categoryProvider = context.read<CategoryProvider>();
    if (categoryId == -1) {
      final customName = _customCategoryController.text.trim();
      if (customName.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama kategori baru wajib diisi.')),
        );
        return;
      }
      final lowerName = customName.toLowerCase();
      final existing = categoryProvider.categories.where((cat) {
        return cat.name.toLowerCase().trim() == lowerName;
      });
      if (existing.isNotEmpty) {
        categoryId = existing.first.id ?? categoryId;
      } else {
        categoryId = await categoryProvider.addCategory(customName, _type);
      }
    }

    if (_type == 'IN' && !_manualIncomeInput) {
      if (_cartItems.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih produk dan jumlah.')),
        );
        return;
      }

      final productProvider = context.read<ProductProvider>();
      for (final item in _cartItems) {
        final product = productProvider.getById(item.productId);
        final available = product?.stock ?? 0;
        if (item.quantity > available) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stok tidak cukup! Sisa: $available')),
          );
          return;
        }
      }
    }

    final now = DateTime.now();
    final txDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );
    final transaction = TransactionModel(
      type: _type,
      amount: amount,
      categoryId: categoryId,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      date: txDateTime.toIso8601String(),
      userId: userId,
    );

    if (_type == 'IN' && !_manualIncomeInput) {
      final items = _cartItems.map((item) {
        return TransactionItemModel(
          transactionId: 0,
          productId: item.productId,
          productName: item.name,
          unitPrice: item.price,
          quantity: item.quantity,
          total: item.price * item.quantity,
        );
      }).toList();
      await context.read<TransactionProvider>().addTransactionWithItems(
            transaction: transaction,
            items: items,
          );
      for (final item in _cartItems) {
        await context.read<ProductProvider>().updateStock(
              item.productId,
              -item.quantity,
            );
      }
    } else {
      await context.read<TransactionProvider>().addTransaction(transaction);
      if (_type == 'IN' && !_manualIncomeInput) {
        // no-op, handled above
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
    });

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate);
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ');
    final showSummaryCard = _type == 'IN' &&
        !_manualIncomeInput &&
        _cartItems.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tambah Transaksi'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Pemasukan'),
                    value: 'IN',
                    groupValue: _type,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _type = value;
                        _selectedCategoryId = null;
                        _manualIncomeInput = false;
                        _customCategoryController.clear();
                        _resetProductSelection();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Pengeluaran'),
                    value: 'OUT',
                    groupValue: _type,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _type = value;
                        _selectedCategoryId = null;
                        _customCategoryController.clear();
                        _resetProductSelection();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Consumer<CategoryProvider>(
              builder: (context, provider, _) {
                final categories = _type == 'IN'
                    ? provider.incomeCategories
                    : provider.expenseCategories;

                if (_selectedCategoryId == null && categories.isNotEmpty) {
                  _selectedCategoryId = categories.first.id;
                }

                if (_type == 'IN' && !_manualIncomeInput) {
                  return const SizedBox.shrink();
                }

                return Column(
                  children: [
                    DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        ...categories.map(
                          (cat) => DropdownMenuItem<int>(
                            value: cat.id,
                            child: Text(cat.name),
                          ),
                        ),
                        const DropdownMenuItem<int>(
                          value: -1,
                          child: Text('Lainnya'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                          if (value != -1) {
                            _customCategoryController.clear();
                          }
                        });
                      },
                    ),
                    if (_selectedCategoryId == -1) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customCategoryController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Kategori Baru',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _type == 'IN' && !_manualIncomeInput
                  ? Column(
                      children: [
                        Expanded(
                          child: _ProductGrid(
                            currency: currency,
                            onManualTap: () {
                              setState(() {
                                _manualIncomeInput = true;
                                _resetProductSelection();
                              });
                            },
                            onSelected:
                                (productId, productName, price, stock) async {
                              await _addToCart(
                                productId: productId,
                                name: productName,
                                price: price,
                                stock: stock,
                              );
                            },
                            isInCart: (productId) {
                              return _cartItems.any(
                                (item) => item.productId == productId,
                              );
                            },
                          ),
                        ),
                        if (_cartItems.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Keranjang',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 140,
                                  child: ListView.separated(
                                    itemCount: _cartItems.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 12),
                                    itemBuilder: (context, index) {
                                      final item = _cartItems[index];
                                      final product =
                                          context.read<ProductProvider>()
                                              .getById(item.productId);
                                      final stock = product?.stock ?? 0;
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${item.name} • ${item.quantity} pcs',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            currency.format(
                                              item.price * item.quantity,
                                            ),
                                            style: const TextStyle(
                                                color: Colors.grey),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit,
                                                size: 18),
                                            onPressed: () =>
                                                _editCartItem(item, stock),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close,
                                                size: 18),
                                            onPressed: () =>
                                                _removeCartItem(item),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    )
                  : ListView(
                      children: [
                        TextField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Jumlah',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Keterangan (Opsional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (_type == 'IN') ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _manualIncomeInput = false;
                                  _resetProductSelection();
                                });
                              },
                              child: const Text('Pilih Produk'),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            if (showSummaryCard)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _descriptionController.text.trim(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currency.format(
                              int.tryParse(_amountController.text.trim()) ?? 0,
                            ),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _resetProductSelection();
                        });
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Tanggal: $dateLabel'),
                ),
                TextButton(
                  onPressed: _pickDate,
                  child: const Text('Pilih Tanggal'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveTransaction,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.currency,
    required this.onManualTap,
    required this.onSelected,
    required this.isInCart,
  });

  final NumberFormat currency;
  final VoidCallback onManualTap;
  final void Function(int id, String name, int price, int stock) onSelected;
  final bool Function(int productId) isInCart;

  @override
  Widget build(BuildContext context) {
    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        final visibleProducts =
            provider.activeProducts.where((product) => product.stock > 0).toList();
        if (visibleProducts.isEmpty) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.store, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Produk belum tersedia',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onManualTap,
                child: const Text('Input Manual'),
              ),
            ],
          );
        }

        final sortedProducts = [...visibleProducts];
        sortedProducts.sort((a, b) {
          final aHasStock = a.stock > 0;
          final bHasStock = b.stock > 0;
          if (aHasStock != bHasStock) {
            return aHasStock ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        return Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pilih Produk',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: onManualTap,
                  child: const Text('Input Manual'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: sortedProducts.length,
                itemBuilder: (context, index) {
                  final product = sortedProducts[index];
                  final inCart = isInCart(product.id ?? -1);
                  return InkWell(
                    onTap: () {
                      if (product.id == null) {
                        return;
                      }
                      onSelected(
                        product.id!,
                        product.name,
                        product.price,
                        product.stock,
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: inCart ? Colors.orange.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: inCart
                              ? Colors.deepOrange
                              : Colors.transparent,
                          width: inCart ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Text(
                            currency.format(product.price),
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Stok: ${product.stock}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
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
}

class _CartItem {
  _CartItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final int productId;
  final String name;
  final int price;
  final int quantity;

  _CartItem copyWith({
    int? productId,
    String? name,
    int? price,
    int? quantity,
  }) {
    return _CartItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
    );
  }
}
