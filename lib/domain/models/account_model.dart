import 'package:hive/hive.dart';

part 'account_model.g.dart';

@HiveType(typeId: 1)
class AccountModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String type; // 'Bank', 'Credit', 'Wallet', 'Cash'

  @HiveField(3)
  final double balance; // For credit cards, this usually tracks the negative amount owed

  @HiveField(4)
  final double creditLimit; // Only applicable for 'Credit' type

  @HiveField(5)
  final int colorHex;

  @HiveField(6)
  final String iconName;

  AccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    this.creditLimit = 0.0,
    this.colorHex = 0xFFAAAAAA,
    this.iconName = 'account_balance',
  });

  AccountModel copyWith({
    String? id,
    String? name,
    String? type,
    double? balance,
    double? creditLimit,
    int? colorHex,
    String? iconName,
  }) {
    return AccountModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      balance: balance ?? this.balance,
      creditLimit: creditLimit ?? this.creditLimit,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
    );
  }
}
