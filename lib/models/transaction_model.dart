class TransactionModel {
  final int? id;
  final String type;
  final int amount;
  final int categoryId;
  final String? description;
  final String date;
  final int userId;
  final String? categoryName;
  final int? productId;
  final int? quantity;

  TransactionModel({
    this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    this.description,
    required this.date,
    required this.userId,
    this.categoryName,
    this.productId,
    this.quantity,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as int?,
      type: map['type'] as String,
      amount: map['amount'] as int,
      categoryId: map['category_id'] as int,
      description: map['description'] as String?,
      date: map['date'] as String,
      userId: map['user_id'] as int,
      categoryName: map['category_name'] as String?,
      productId: map['product_id'] as int?,
      quantity: map['quantity'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'amount': amount,
      'category_id': categoryId,
      'description': description,
      'date': date,
      'user_id': userId,
      'product_id': productId,
      'quantity': quantity,
    };
  }
}
