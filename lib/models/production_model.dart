class ProductionModel {
  final int? id;
  final String productName;
  final int quantity;
  final String date;
  final int userId;

  ProductionModel({
    this.id,
    required this.productName,
    required this.quantity,
    required this.date,
    required this.userId,
  });

  factory ProductionModel.fromMap(Map<String, dynamic> map) {
    return ProductionModel(
      id: map['id'] as int?,
      productName: map['product_name'] as String,
      quantity: map['quantity'] as int,
      date: map['date'] as String,
      userId: map['user_id'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_name': productName,
      'quantity': quantity,
      'date': date,
      'user_id': userId,
    };
  }
}
