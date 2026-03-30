import 'package:hive/hive.dart';

part 'category_model.g.dart';

@HiveType(typeId: 2)
class CategoryModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String type; // 'Expense', 'Income', 'Transfer'

  @HiveField(3)
  final int colorHex;

  @HiveField(4)
  final String iconName;

  CategoryModel({
    required this.id,
    required this.name,
    required this.type,
    this.colorHex = 0xFFAAAAAA,
    this.iconName = 'category',
  });

  CategoryModel copyWith({
    String? id,
    String? name,
    String? type,
    int? colorHex,
    String? iconName,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
    );
  }
}
