class ProductModel {
  final int? id;
  final String name;
  final int price;
  final int stock;

  ProductModel({
    this.id,
    required this.name,
    required this.price,
    required this.stock,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      price: map['price'] as int,
      stock: map['stock'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'stock': stock,
    };
  }
}
