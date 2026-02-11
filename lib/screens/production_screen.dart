import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/production_model.dart';
import '../models/product_model.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import '../providers/production_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/product_image_service.dart';
import '../widgets/product_avatar.dart';

enum _StockListFilter { active, archived, all }

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
  final TextEditingController _stockSearchController =
      TextEditingController();
  bool _isLoading = false;
  bool _selectionMode = false;
  final Set<int> _selectedProductIds = {};
  String _stockSearchQuery = '';
  _StockListFilter _stockListFilter = _StockListFilter.active;

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
    _stockSearchController.dispose();
    super.dispose();
  }

  void _toggleSelection(ProductModel product) {
    final id = product.id;
    if (id == null) {
      return;
    }
    setState(() {
      if (_selectedProductIds.contains(id)) {
        _selectedProductIds.remove(id);
      } else {
        _selectedProductIds.add(id);
      }
      if (_selectedProductIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _enterSelectionMode(ProductModel product) {
    final id = product.id;
    if (id == null) {
      return;
    }
    setState(() {
      _selectionMode = true;
      _selectedProductIds.add(id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedProductIds.clear();
    });
  }

  bool _matchesStockListFilter(ProductModel product) {
    switch (_stockListFilter) {
      case _StockListFilter.active:
        return product.isActive;
      case _StockListFilter.archived:
        return !product.isActive;
      case _StockListFilter.all:
        return true;
    }
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final productId = product.id;
    if (productId == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus produk permanen?'),
        content: Text(
          'Produk "${product.name}" akan dihapus permanen. '
          'Aksi ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final status =
        await context.read<ProductProvider>().deleteProductSafely(productId);
    if (!mounted) {
      return;
    }
    switch (status) {
      case ProductDeleteStatus.deleted:
        await ProductImageService.deleteProductImage(productId);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produk berhasil dihapus permanen.')),
        );
        return;
      case ProductDeleteStatus.blockedHasStock:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produk tidak bisa dihapus karena stok masih ada.'),
          ),
        );
        return;
      case ProductDeleteStatus.blockedHasTransactions:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Produk tidak bisa dihapus karena sudah memiliki riwayat transaksi. '
              'Silakan arsipkan produk.',
            ),
          ),
        );
        return;
      case ProductDeleteStatus.notFound:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produk tidak ditemukan.')),
        );
        return;
    }
  }

  Future<XFile?> _pickProductImage(ImageSource source) async {
    try {
      return await ImagePicker().pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    } catch (_) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuka pemilih foto.')),
      );
      return null;
    }
  }

  Future<void> _bulkSetActive(bool isActive) async {
    final ids = _selectedProductIds.toList();
    if (!isActive) {
      final products = context.read<ProductProvider>().products;
      final blocked = products
          .where((product) =>
              product.id != null &&
              ids.contains(product.id) &&
              product.stock > 0)
          .toList();
      if (blocked.isNotEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal arsipkan. ${blocked.length} produk masih punya stok.',
            ),
          ),
        );
        return;
      }
    }
    await context.read<ProductProvider>().updateProductsActive(
          ids: ids,
          isActive: isActive,
        );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isActive ? 'Produk diaktifkan.' : 'Produk diarsipkan.',
        ),
      ),
    );
    _clearSelection();
  }

  Future<void> _addProduct() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final minStockController = TextEditingController(text: '0');
    bool isActive = true;
    XFile? selectedImage;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tambah Produk Baru'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFFF3E5E5),
                      backgroundImage:
                          selectedImage != null
                              ? FileImage(File(selectedImage!.path))
                              : null,
                      child:
                          selectedImage == null
                              ? const Icon(
                                Icons.image_outlined,
                                color: Color(0xFF8D1B3D),
                              )
                              : null,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final image = await _pickProductImage(
                              ImageSource.gallery,
                            );
                            if (image == null) {
                              return;
                            }
                            setState(() {
                              selectedImage = image;
                            });
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeri'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final image = await _pickProductImage(
                              ImageSource.camera,
                            );
                            if (image == null) {
                              return;
                            }
                            setState(() {
                              selectedImage = image;
                            });
                          },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Kamera'),
                        ),
                        if (selectedImage != null)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                selectedImage = null;
                              });
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Hapus'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: minStockController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Batas Stok Minimum',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Produk Aktif'),
                      value: isActive,
                      onChanged: (value) {
                        setState(() {
                          isActive = value;
                        });
                      },
                    ),
                  ],
                ),
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
      },
    );

    if (result != true) {
      return;
    }

    final name = nameController.text.trim();
    final price = int.tryParse(priceController.text.trim()) ?? 0;
    final minStock = int.tryParse(minStockController.text.trim()) ?? 0;
    if (name.isEmpty || price <= 0 || minStock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan harga wajib diisi.')),
      );
      return;
    }

    final newProductId = await context.read<ProductProvider>().addProduct(
          name,
          price,
          minStock: minStock,
          isActive: isActive,
        );
    var imageSaved = true;
    if (selectedImage != null) {
      imageSaved = await ProductImageService.saveProductImage(
        productId: newProductId,
        sourceImage: selectedImage!,
      );
      await context.read<ProductProvider>().loadProducts();
    }
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          imageSaved
              ? 'Produk baru ditambahkan.'
              : 'Produk ditambahkan, tapi foto gagal disimpan.',
        ),
      ),
    );
  }

  Future<void> _editProduct(ProductModel product) async {
    final nameController = TextEditingController(text: product.name);
    final priceController = TextEditingController(text: '${product.price}');
    final minStockController =
        TextEditingController(text: '${product.minStock}');
    File? existingImage;
    if (product.id != null) {
      existingImage = await ProductImageService.getProductImage(product.id!);
    }
    XFile? selectedImage;
    bool removeCurrentImage = false;
    bool isActive = product.isActive;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final currentImage = !removeCurrentImage ? existingImage : null;
            final imageProvider =
                selectedImage != null
                    ? FileImage(File(selectedImage!.path))
                    : (currentImage != null ? FileImage(currentImage) : null);
            return AlertDialog(
              title: const Text('Edit Produk'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFFF3E5E5),
                      backgroundImage: imageProvider,
                      child:
                          imageProvider == null
                              ? Text(
                                product.name.trim().isEmpty
                                    ? '?'
                                    : product.name
                                        .trim()
                                        .substring(0, 1)
                                        .toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF8D1B3D),
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                              : null,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final image = await _pickProductImage(
                              ImageSource.gallery,
                            );
                            if (image == null) {
                              return;
                            }
                            setState(() {
                              selectedImage = image;
                              removeCurrentImage = false;
                            });
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeri'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final image = await _pickProductImage(
                              ImageSource.camera,
                            );
                            if (image == null) {
                              return;
                            }
                            setState(() {
                              selectedImage = image;
                              removeCurrentImage = false;
                            });
                          },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Kamera'),
                        ),
                        if (selectedImage != null ||
                            (!removeCurrentImage && existingImage != null))
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                selectedImage = null;
                                removeCurrentImage = true;
                              });
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Hapus'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: minStockController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Batas Stok Minimum',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Produk Aktif'),
                      value: isActive,
                      onChanged: (value) {
                        setState(() {
                          isActive = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Stok Saat Ini: ${product.stock}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
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
      },
    );

    if (result != true) {
      return;
    }

    final name = nameController.text.trim();
    final price = int.tryParse(priceController.text.trim()) ?? 0;
    final minStock = int.tryParse(minStockController.text.trim()) ?? 0;
    if (name.isEmpty || price <= 0 || minStock < 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan harga wajib diisi.')),
      );
      return;
    }
    if (!isActive && product.stock > 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stok ${product.name} masih ${product.stock} pcs. '
            'Habiskan dulu sebelum arsip.',
          ),
        ),
      );
      return;
    }

    if (product.id != null) {
      await context.read<ProductProvider>().updateProduct(
            id: product.id!,
            name: name,
            price: price,
            minStock: minStock,
            isActive: isActive,
          );
      bool imageSaved = true;
      if (selectedImage != null) {
        imageSaved = await ProductImageService.saveProductImage(
          productId: product.id!,
          sourceImage: selectedImage!,
        );
        await context.read<ProductProvider>().loadProducts();
      } else if (removeCurrentImage) {
        imageSaved = await ProductImageService.deleteProductImage(product.id!);
        await context.read<ProductProvider>().loadProducts();
      }
      if (!mounted) {
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imageSaved
                ? 'Produk diperbarui.'
                : 'Produk diperbarui, tapi foto gagal diproses.',
          ),
        ),
      );
    }
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
    final noteController = TextEditingController();
    const reasons = [
      'Rusak / Basi',
      'Sedekah / Sosial',
      'Konsumsi Pribadi / Tester',
      'Hilang / Selisih Stok',
      'Lainnya',
    ];
    String selectedReason = reasons.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Kurangi Stok - $productName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    decoration: const InputDecoration(
                      labelText: 'Alasan',
                    ),
                    items: reasons
                        .map(
                          (reason) => DropdownMenuItem<String>(
                            value: reason,
                            child: Text(reason),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        selectedReason = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Jumlah yang dikurangi',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Catatan Tambahan (Opsional)',
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
                  child: const Text('Catat'),
                ),
              ],
            );
          },
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

    final reasonTag = selectedReason
        .split('/')
        .first
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_');
    final note = noteController.text.trim();
    final noteSuffix = note.isEmpty ? '' : ' - $note';
    await context.read<TransactionProvider>().addWasteTransaction(
          productId: productId,
          quantity: qty,
          userId: userId,
          categoryId: wasteCategoryId,
          description: '[$reasonTag] $productName ($qty pcs)$noteSuffix',
          date: DateTime.now().toIso8601String(),
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
          final sortedByStock = [...products]
            ..sort((a, b) {
              if (a.isActive != b.isActive) {
                return a.isActive ? -1 : 1;
              }
              if (a.stock != b.stock) {
                return b.stock.compareTo(a.stock);
              }
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          final query = _stockSearchQuery.trim().toLowerCase();
          final filteredBySearch = query.isEmpty
              ? sortedByStock
              : sortedByStock
                  .where((product) =>
                      product.name.toLowerCase().contains(query))
                  .toList();
          final filteredProducts = filteredBySearch
              .where(_matchesStockListFilter)
              .toList();
          final now = DateTime.now();
          final wasteToday = transactionProvider.transactions.where((tx) {
            if (tx.type != 'WASTE') {
              return false;
            }
            final parsed = DateTime.tryParse(tx.date);
            if (parsed == null) {
              return false;
            }
            return parsed.year == now.year &&
                parsed.month == now.month &&
                parsed.day == now.day;
          }).toList();

          final totalStock =
              products.fold<int>(0, (sum, product) => sum + product.stock);

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
                        'Total Stok Tersedia',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$totalStock Pcs',
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
                  padding: const EdgeInsets.all(8),
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
                  child: ExpansionTile(
                    title: const Text(
                      'Stok Produk',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    initiallyExpanded: false,
                    children: [
                      const SizedBox(height: 4),
                      if (_selectionMode)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_selectedProductIds.length} dipilih',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _bulkSetActive(true),
                                child: const Text('Aktifkan'),
                              ),
                              TextButton(
                                onPressed: () => _bulkSetActive(false),
                                child: const Text('Arsipkan'),
                              ),
                              TextButton(
                                onPressed: _clearSelection,
                                child: const Text('Batal'),
                              ),
                            ],
                          ),
                        ),
                      if (sortedByStock.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: TextField(
                            controller: _stockSearchController,
                            onChanged: (value) {
                              setState(() {
                                _stockSearchQuery = value;
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Cari produk...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _stockSearchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        setState(() {
                                          _stockSearchController.clear();
                                          _stockSearchQuery = '';
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Aktif'),
                              selected: _stockListFilter == _StockListFilter.active,
                              onSelected: (_) {
                                setState(() {
                                  _stockListFilter = _StockListFilter.active;
                                });
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Arsip'),
                              selected:
                                  _stockListFilter == _StockListFilter.archived,
                              onSelected: (_) {
                                setState(() {
                                  _stockListFilter = _StockListFilter.archived;
                                });
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Semua'),
                              selected: _stockListFilter == _StockListFilter.all,
                              onSelected: (_) {
                                setState(() {
                                  _stockListFilter = _StockListFilter.all;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      if (sortedByStock.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Belum ada produk',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else if (filteredProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Produk tidak ditemukan pada filter ini',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ...filteredProducts.map((product) {
                          final id = product.id;
                          final isSelected =
                              id != null && _selectedProductIds.contains(id);
                          final isArchived = !product.isActive;
                          final textColor =
                              isArchived ? Colors.grey : Colors.black87;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            tileColor:
                                isArchived ? Colors.grey.shade200 : null,
                            leading: _selectionMode
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (_) => _toggleSelection(product),
                                  )
                                : ProductAvatar(
                                    productId: product.id,
                                    productName: product.name,
                                    radius: 20,
                                  ),
                            title: Text(
                              product.name,
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: Text(
                              'Stok: ${product.stock} • Min: ${product.minStock}${product.isActive ? '' : ' • Arsip'}',
                              style: TextStyle(color: textColor),
                            ),
                            onTap: _selectionMode
                                ? () => _toggleSelection(product)
                                : null,
                            onLongPress: _selectionMode
                                ? null
                                : () => _enterSelectionMode(product),
                            trailing: _selectionMode
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Color(0xFF1565C0)),
                                        onPressed: () => _editProduct(product),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (value) async {
                                          if (value == 'waste') {
                                            if (product.id != null) {
                                              await _wasteStock(
                                                product.id!,
                                                product.name,
                                              );
                                            }
                                            return;
                                          }
                                          if (value == 'toggle') {
                                            if (!product.isActive &&
                                                product.id != null) {
                                              await context
                                                  .read<ProductProvider>()
                                                  .updateProductsActive(
                                                    ids: [product.id!],
                                                    isActive: true,
                                                  );
                                              if (!mounted) {
                                                return;
                                              }
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '${product.name} diaktifkan.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            if (product.stock > 0) {
                                              if (!mounted) {
                                                return;
                                              }
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Stok ${product.name} masih ${product.stock} pcs. '
                                                    'Habiskan dulu sebelum arsip.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            if (product.id != null) {
                                              await context
                                                  .read<ProductProvider>()
                                                  .updateProductsActive(
                                                    ids: [product.id!],
                                                    isActive: false,
                                                  );
                                              if (!mounted) {
                                                return;
                                              }
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '${product.name} diarsipkan.',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          if (value == 'delete') {
                                            await _deleteProduct(product);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (product.stock > 0)
                                            const PopupMenuItem<String>(
                                              value: 'waste',
                                              child: Text('Kurangi stok'),
                                            ),
                                          PopupMenuItem<String>(
                                            value: 'toggle',
                                            child: Text(
                                              product.isActive
                                                  ? 'Arsipkan produk'
                                                  : 'Aktifkan produk',
                                            ),
                                          ),
                                          const PopupMenuItem<String>(
                                            value: 'delete',
                                            child: Text('Hapus permanen'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
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
                  child: ExpansionTile(
                    title: const Text(
                      'Daftar Produksi Hari Ini',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    initiallyExpanded: true,
                    children: [
                      const SizedBox(height: 4),
                      if (productionProvider.todayItems.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Belum ada produksi hari ini',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ...productionProvider.todayItems.map((item) {
                          final product = products
                              .where((p) => p.name == item.productName)
                              .toList();
                          final stock =
                              product.isNotEmpty ? product.first.stock : 0;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
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
                  padding: const EdgeInsets.all(8),
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
                  child: ExpansionTile(
                    title: const Text(
                      'Barang Rusak/Basi Hari Ini',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    initiallyExpanded: false,
                    children: [
                      const SizedBox(height: 4),
                      if (wasteToday.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Belum ada barang rusak hari ini',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ...wasteToday.map((item) {
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
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
