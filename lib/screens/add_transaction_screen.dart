import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants/default_categories.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../models/transaction_item_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/product_avatar.dart';

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
  final TextEditingController _productSearchController =
      TextEditingController();

  String _type = 'IN';
  int? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  bool _manualIncomeInput = false;
  bool _isLoading = false;
  bool _isCartExpanded = false;
  final List<_CartItem> _cartItems = [];
  String _productSearchQuery = '';

  int? _preferredManualIncomeCategoryId(List<CategoryModel> categories) {
    final fallbackName = DefaultCategories.incomeFallback.toLowerCase().trim();
    final primaryName = DefaultCategories.incomePrimary.toLowerCase().trim();
    for (final category in categories) {
      if (category.name.toLowerCase().trim() == fallbackName) {
        return category.id;
      }
    }
    for (final category in categories) {
      final name = category.name.toLowerCase().trim();
      if (name != primaryName) {
        return category.id;
      }
    }
    return categories.isNotEmpty ? categories.first.id : null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) {
      _type = widget.initialType!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      Provider.of<CategoryProvider>(
        context,
        listen: false,
      ).setCurrentRole(authProvider.currentUser?.role);
      Provider.of<CategoryProvider>(context, listen: false).loadCategories();
      Provider.of<ProductProvider>(context, listen: false).loadProducts();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _customCategoryController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  Future<int?> _showQuantityDialog({int? initialQty}) async {
    FocusScope.of(context).unfocus();
    final controller = TextEditingController(
      text: initialQty != null ? '$initialQty' : '',
    );
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
    _productSearchController.clear();
    _productSearchQuery = '';
    _isCartExpanded = false;
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
    final existingIndex = _cartItems.indexWhere(
      (item) => item.productId == productId,
    );
    final currentQty =
        existingIndex != -1 ? _cartItems[existingIndex].quantity : null;
    final qty = await _showQuantityDialog(initialQty: currentQty);
    if (!mounted) {
      return;
    }
    if (qty == null || qty <= 0) {
      return;
    }
    if (existingIndex != -1) {
      if (qty > stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stok tidak cukup! Sisa: $stock')),
        );
        return;
      }
      setState(() {
        _cartItems[existingIndex] = _cartItems[existingIndex].copyWith(
          quantity: qty,
        );
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
    _descriptionController.text = 'Penjualan ${_cartItems.length} item';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Stok tidak cukup! Sisa: $stock')));
      return;
    }
    setState(() {
      final index = _cartItems.indexWhere(
        (entry) => entry.productId == item.productId,
      );
      if (index != -1) {
        _cartItems[index] = _cartItems[index].copyWith(quantity: newQty);
      }
      _amountController.text = _cartTotal().toString();
      _descriptionController.text = 'Penjualan ${_cartItems.length} item';
    });
  }

  void _removeCartItem(_CartItem item) {
    setState(() {
      _cartItems.removeWhere((entry) => entry.productId == item.productId);
      _amountController.text =
          _cartItems.isEmpty ? '' : _cartTotal().toString();
      _descriptionController.text =
          _cartItems.isEmpty ? '' : 'Penjualan ${_cartItems.length} item';
      if (_cartItems.isEmpty) {
        _isCartExpanded = false;
      }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lengkapi data transaksi.')));
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;

    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User belum login.')));
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
      description:
          _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
      date: txDateTime.toIso8601String(),
      userId: userId,
    );

    if (_type == 'IN' && !_manualIncomeInput) {
      final items =
          _cartItems.map((item) {
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
    final isTypeLocked = widget.initialType != null;
    final dateLabel = DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate);
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final showCartSection =
        _type == 'IN' && !_manualIncomeInput && _cartItems.isNotEmpty;
    final cartTotal = _cartTotal();

    return Scaffold(
      appBar: AppBar(
        title: Text(_type == 'IN' ? 'Catat Pemasukan' : 'Catat Pengeluaran'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isTypeLocked) ...[
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
            ],
            Consumer<CategoryProvider>(
              builder: (context, provider, _) {
                final allCategories =
                    _type == 'IN'
                        ? provider.incomeCategories
                        : provider.expenseCategories;
                final categories =
                    _type == 'IN' && _manualIncomeInput
                        ? allCategories
                            .where(
                              (category) =>
                                  category.name.toLowerCase().trim() !=
                                  DefaultCategories.incomePrimary
                                      .toLowerCase()
                                      .trim(),
                            )
                            .toList()
                        : allCategories;

                if (_type == 'IN' &&
                    _manualIncomeInput &&
                    categories.isNotEmpty &&
                    (_selectedCategoryId == null ||
                        !categories.any(
                          (cat) => cat.id == _selectedCategoryId,
                        ))) {
                  _selectedCategoryId = _preferredManualIncomeCategoryId(
                    categories,
                  );
                }

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
                    if (_type == 'IN' && _manualIncomeInput) ...[
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Input manual tidak memengaruhi stok produk.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ],
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
              child:
                  _type == 'IN' && !_manualIncomeInput
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
                              searchController: _productSearchController,
                              searchQuery: _productSearchQuery,
                              onSearchChanged: (value) {
                                setState(() {
                                  _productSearchQuery = value;
                                });
                              },
                              onClearSearch: () {
                                setState(() {
                                  _productSearchController.clear();
                                  _productSearchQuery = '';
                                });
                              },
                              onSelected: (
                                productId,
                                productName,
                                price,
                                stock,
                              ) async {
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
            if (showCartSection && _isCartExpanded)
              Container(
                margin: const EdgeInsets.only(top: 12),
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
                child: SizedBox(
                  height: 160,
                  child: ListView.separated(
                    itemCount: _cartItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final item = _cartItems[index];
                      final product = context.read<ProductProvider>().getById(
                        item.productId,
                      );
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
                            currency.format(item.price * item.quantity),
                            style: const TextStyle(color: Colors.grey),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _editCartItem(item, stock),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _removeCartItem(item),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            if (showCartSection)
              Container(
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _isCartExpanded = !_isCartExpanded;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_cart_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_cartItems.length} Produk',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          currency.format(cartTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8D1B3D),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isCartExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Kosongkan keranjang',
                          onPressed: () {
                            setState(() {
                              _resetProductSelection();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Tanggal: $dateLabel')),
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
                child:
                    _isLoading
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
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSelected,
    required this.isInCart,
  });

  final NumberFormat currency;
  final VoidCallback onManualTap;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final void Function(int id, String name, int price, int stock) onSelected;
  final bool Function(int productId) isInCart;

  @override
  Widget build(BuildContext context) {
    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        final visibleProducts =
            provider.activeProducts
                .where((product) => product.stock > 0)
                .toList();
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
        final query = searchQuery.trim().toLowerCase();
        final filteredProducts =
            query.isEmpty
                ? sortedProducts
                : sortedProducts
                    .where(
                      (product) => product.name.toLowerCase().contains(query),
                    )
                    .toList();

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
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Cari produk...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    searchQuery.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: onClearSearch,
                        ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  filteredProducts.isEmpty
                      ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Produk tidak ditemukan',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: onClearSearch,
                            child: const Text('Reset Pencarian'),
                          ),
                        ],
                      )
                      : LayoutBuilder(
                        builder: (context, constraints) {
                          final maxWidth = constraints.maxWidth;
                          final crossAxisCount =
                              maxWidth < 700 ? 2 : (maxWidth < 1100 ? 3 : 4);
                          final childAspectRatio =
                              maxWidth < 700
                                  ? 1.18
                                  : (maxWidth < 1100 ? 1.3 : 1.4);
                          final tileWidth =
                              (maxWidth - ((crossAxisCount - 1) * 12)) /
                              crossAxisCount;
                          final avatarRadius =
                              (maxWidth < 700
                                      ? (tileWidth * 0.17).clamp(30.0, 50.0)
                                      : (tileWidth * 0.14).clamp(26.0, 44.0))
                                  .toDouble();

                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: childAspectRatio,
                                ),
                            itemCount: filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = filteredProducts[index];
                              final inCart = isInCart(product.id ?? -1);
                              final addButtonSize =
                                  ((tileWidth * 0.18).clamp(
                                    30.0,
                                    36.0,
                                  )).toDouble();

                              void addProduct() {
                                if (product.id == null) {
                                  return;
                                }
                                onSelected(
                                  product.id!,
                                  product.name,
                                  product.price,
                                  product.stock,
                                );
                              }

                              return InkWell(
                                onTap: addProduct,
                                borderRadius: BorderRadius.circular(12),
                                child: Ink(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        inCart
                                            ? Colors.orange.shade50
                                            : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          inCart
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          ProductAvatar(
                                            productId: product.id,
                                            productName: product.name,
                                            radius: avatarRadius,
                                          ),
                                          Positioned(
                                            right: -6,
                                            bottom: -6,
                                            child: Material(
                                              color: Colors.white,
                                              shape: const CircleBorder(),
                                              elevation: 3,
                                              child: InkWell(
                                                onTap: addProduct,
                                                customBorder:
                                                    const CircleBorder(),
                                                child: SizedBox(
                                                  width: addButtonSize,
                                                  height: addButtonSize,
                                                  child: const Icon(
                                                    Icons.add,
                                                    color: Color(0xFF1B8F3A),
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        currency.format(product.price),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFF8D1B3D),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        product.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Stok: ${product.stock}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
