class DefaultCategory {
  const DefaultCategory({required this.name, required this.type});

  final String name;
  final String type;

  String get normalizedName => name.toLowerCase().trim();
}

class DefaultCategories {
  static const String incomePrimary = 'Penjualan Kue';
  static const String incomeFallback = 'Pemasukan Lain';
  static const String expenseRawMaterials = 'Bahan Baku';
  static const String expenseOperational = 'Operasional';
  static const String expenseSalary = 'Gaji';

  static const List<DefaultCategory> system = [
    DefaultCategory(name: incomePrimary, type: 'IN'),
    DefaultCategory(name: incomeFallback, type: 'IN'),
    DefaultCategory(name: expenseRawMaterials, type: 'OUT'),
    DefaultCategory(name: expenseOperational, type: 'OUT'),
    DefaultCategory(name: expenseSalary, type: 'OUT'),
  ];

  static final Set<String> _normalizedSystemNames = {
    for (final category in system) category.normalizedName,
  };

  static bool isSystemCategoryName(String name) {
    return _normalizedSystemNames.contains(name.toLowerCase().trim());
  }

  static List<DefaultCategory> byType(String type) {
    return system.where((category) => category.type == type).toList();
  }
}
