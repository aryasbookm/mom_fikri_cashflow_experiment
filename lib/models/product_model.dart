class ProductModel {
  final int? id;
  final String name;
  final int price;
  final int stock;
  final int minStock;
  final bool isActive;

  ProductModel({
    this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.minStock,
    required this.isActive,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      price: map['price'] as int,
      stock: map['stock'] as int? ?? 0,
      minStock: map['min_stock'] as int? ?? 5,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'stock': stock,
      'min_stock': minStock,
      'is_active': isActive ? 1 : 0,
    };
  }
}
