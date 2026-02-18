import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/category_model.dart';
import '../providers/category_provider.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  String _typeFilter = 'IN';
  String _statusFilter = 'ALL';

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories();
    });
  }

  Future<void> _renameCategory(CategoryModel category) async {
    final controller = TextEditingController(text: category.name);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ubah Nama Kategori'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nama kategori',
              border: OutlineInputBorder(),
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
    if (save != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    final result = await context.read<CategoryProvider>().renameCategory(
      category: category,
      newName: controller.text,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            _typeFilter == 'IN'
                ? 'Tambah Kategori Pemasukan'
                : 'Tambah Kategori Pengeluaran',
          ),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nama kategori',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.of(context).pop(true),
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

    if (created != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    try {
      await context.read<CategoryProvider>().addCategory(
        controller.text,
        _typeFilter,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori berhasil ditambahkan.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _deleteCategory(CategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Kategori?'),
          content: Text(
            'Kategori "${category.name}" akan dihapus permanen jika belum pernah dipakai transaksi.',
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
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    final result = await context.read<CategoryProvider>().deleteCategory(
      category,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _toggleCategoryStatus(CategoryModel category) async {
    final targetActive = !category.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            targetActive ? 'Aktifkan Kategori?' : 'Arsipkan Kategori?',
          ),
          content: Text(
            targetActive
                ? 'Kategori "${category.name}" akan aktif kembali dan muncul di input transaksi.'
                : 'Kategori "${category.name}" akan disembunyikan dari input transaksi baru.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(targetActive ? 'Aktifkan' : 'Arsipkan'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    final result = await context.read<CategoryProvider>().toggleCategoryActive(
      category: category,
      isActive: targetActive,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Kategori')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCategory,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Kategori'),
      ),
      body: Consumer<CategoryProvider>(
        builder: (context, provider, _) {
          final categories =
              provider.categories
                  .where((category) => category.type == _typeFilter)
                  .where((category) {
                    if (_statusFilter == 'ACTIVE') {
                      return category.isActive;
                    }
                    if (_statusFilter == 'ARCHIVED') {
                      return !category.isActive;
                    }
                    return true;
                  })
                  .toList()
                ..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Pemasukan'),
                      selected: _typeFilter == 'IN',
                      onSelected: (_) {
                        setState(() {
                          _typeFilter = 'IN';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Pengeluaran'),
                      selected: _typeFilter == 'OUT',
                      onSelected: (_) {
                        setState(() {
                          _typeFilter = 'OUT';
                        });
                      },
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sistem: tidak bisa diubah/hapus/arsip. Arsip: tidak muncul di input transaksi baru.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Semua'),
                      selected: _statusFilter == 'ALL',
                      onSelected: (_) {
                        setState(() {
                          _statusFilter = 'ALL';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Aktif'),
                      selected: _statusFilter == 'ACTIVE',
                      onSelected: (_) {
                        setState(() {
                          _statusFilter = 'ACTIVE';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Arsip'),
                      selected: _statusFilter == 'ARCHIVED',
                      onSelected: (_) {
                        setState(() {
                          _statusFilter = 'ARCHIVED';
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child:
                    categories.isEmpty
                        ? const Center(
                          child: Text(
                            'Belum ada kategori.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                        : ListView.separated(
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            final protected = provider.isProtectedCategory(
                              category,
                            );
                            final isUsed =
                                category.id != null &&
                                (provider.categoryUsage[category.id!] ?? false);
                            final canRename = !protected;
                            final canArchive = !protected && category.isActive;
                            final canRestore = !protected && !category.isActive;
                            final canDelete = !protected && !isUsed;
                            return ListTile(
                              leading: Icon(
                                protected
                                    ? Icons.lock_outline
                                    : !category.isActive
                                    ? Icons.archive_outlined
                                    : isUsed
                                    ? Icons.info_outline
                                    : Icons.label_outline,
                                color:
                                    protected
                                        ? Colors.grey.shade700
                                        : !category.isActive
                                        ? Colors.blueGrey.shade700
                                        : isUsed
                                        ? Colors.orange.shade700
                                        : Colors.green.shade700,
                              ),
                              subtitle: Text(
                                protected
                                    ? 'Kategori sistem: tidak bisa diubah/hapus/arsip'
                                    : !category.isActive
                                    ? 'Kategori custom: diarsipkan (disembunyikan dari input transaksi)'
                                    : isUsed
                                    ? 'Kategori custom: dipakai transaksi, tidak bisa dihapus'
                                    : 'Kategori custom: bisa diubah/hapus',
                              ),
                              isThreeLine: true,
                              titleTextStyle:
                                  Theme.of(context).textTheme.titleMedium,
                              subtitleTextStyle: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.grey.shade700),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              dense: false,
                              horizontalTitleGap: 12,
                              minLeadingWidth: 24,
                              visualDensity: const VisualDensity(vertical: 0),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Color(0xFF1565C0),
                                    ),
                                    tooltip:
                                        canRename
                                            ? 'Ubah nama'
                                            : 'Kategori sistem tidak bisa diubah',
                                    onPressed:
                                        canRename
                                            ? () => _renameCategory(category)
                                            : null,
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      category.isActive
                                          ? Icons.archive_outlined
                                          : Icons.unarchive_outlined,
                                      color: Colors.blueGrey,
                                    ),
                                    tooltip:
                                        (canArchive || canRestore)
                                            ? (category.isActive
                                                ? 'Arsipkan'
                                                : 'Aktifkan')
                                            : protected
                                            ? 'Kategori sistem tidak bisa diarsipkan'
                                            : 'Status kategori tidak dapat diubah',
                                    onPressed:
                                        (canArchive || canRestore)
                                            ? () =>
                                                _toggleCategoryStatus(category)
                                            : null,
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    tooltip:
                                        canDelete
                                            ? 'Hapus permanen'
                                            : protected
                                            ? 'Kategori sistem tidak bisa dihapus'
                                            : 'Kategori sudah dipakai transaksi',
                                    onPressed:
                                        canDelete
                                            ? () => _deleteCategory(category)
                                            : null,
                                  ),
                                ],
                              ),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(category.name),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      _buildStatusChip(
                                        protected ? 'Sistem' : 'Custom',
                                        protected
                                            ? Colors.grey.shade700
                                            : Colors.green.shade700,
                                      ),
                                      _buildStatusChip(
                                        category.isActive ? 'Aktif' : 'Arsip',
                                        category.isActive
                                            ? Colors.teal.shade700
                                            : Colors.blueGrey.shade700,
                                      ),
                                      if (isUsed)
                                        _buildStatusChip(
                                          'Dipakai ${provider.categoryUsageCount[category.id!] ?? 0} transaksi',
                                          Colors.orange.shade700,
                                        ),
                                    ],
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
