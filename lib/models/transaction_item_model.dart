class TransactionItemModel {
  final int? id;
  final int transactionId;
  final int? productId;
  final String productName;
  final int unitPrice;
  final int quantity;
  final int total;

  TransactionItemModel({
    this.id,
    required this.transactionId,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.total,
  });

  factory TransactionItemModel.fromMap(Map<String, dynamic> map) {
    return TransactionItemModel(
      id: map['id'] as int?,
      transactionId: map['transaction_id'] as int,
      productId: map['product_id'] as int?,
      productName: map['product_name'] as String,
      unitPrice: map['unit_price'] as int,
      quantity: map['quantity'] as int,
      total: map['total'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'product_id': productId,
      'product_name': productName,
      'unit_price': unitPrice,
      'quantity': quantity,
      'total': total,
    };
  }

  TransactionItemModel copyWith({
    int? id,
    int? transactionId,
    int? productId,
    String? productName,
    int? unitPrice,
    int? quantity,
    int? total,
  }) {
    return TransactionItemModel(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      total: total ?? this.total,
    );
  }
}
