class CategoryModel {
  final int? id;
  final String name;
  final String type;
  final bool isActive;

  CategoryModel({
    this.id,
    required this.name,
    required this.type,
    this.isActive = true,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'is_active': isActive ? 1 : 0,
    };
  }
}
