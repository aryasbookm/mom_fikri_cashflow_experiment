class DeletedTransaction {
  final int? id;
  final int? originalId;
  final String type;
  final int amount;
  final int? categoryId;
  final String? category;
  final String? description;
  final String date;
  final int? userId;
  final int? productId;
  final int? quantity;
  final String deletedAt;
  final String deletedBy;
  final String reason;

  DeletedTransaction({
    this.id,
    this.originalId,
    required this.type,
    required this.amount,
    this.categoryId,
    this.category,
    this.description,
    required this.date,
    this.userId,
    this.productId,
    this.quantity,
    required this.deletedAt,
    required this.deletedBy,
    required this.reason,
  });

  factory DeletedTransaction.fromMap(Map<String, dynamic> map) {
    return DeletedTransaction(
      id: map['id'] as int?,
      originalId: map['original_id'] as int?,
      type: map['type'] as String,
      amount: map['amount'] as int,
      categoryId: map['category_id'] as int?,
      category: map['category'] as String?,
      description: map['description'] as String?,
      date: map['date'] as String,
      userId: map['user_id'] as int?,
      productId: map['product_id'] as int?,
      quantity: map['quantity'] as int?,
      deletedAt: map['deleted_at'] as String,
      deletedBy: map['deleted_by'] as String,
      reason: map['reason'] as String,
    );
  }
}
