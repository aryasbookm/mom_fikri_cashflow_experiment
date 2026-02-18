class DefaultCategory {
  const DefaultCategory({required this.name, required this.type});

  final String name;
  final String type;

  String get normalizedName => name.toLowerCase().trim();
}

class DefaultCategories {
  static const List<DefaultCategory> system = [
    DefaultCategory(name: 'Penjualan Kue', type: 'IN'),
    DefaultCategory(name: 'Pemasukan Lain', type: 'IN'),
    DefaultCategory(name: 'Bahan Baku', type: 'OUT'),
    DefaultCategory(name: 'Operasional', type: 'OUT'),
    DefaultCategory(name: 'Gaji', type: 'OUT'),
  ];
}
