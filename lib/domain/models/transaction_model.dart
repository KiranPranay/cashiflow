import 'package:hive/hive.dart';

part 'transaction_model.g.dart';

@HiveType(typeId: 0)
class TransactionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final double amount;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final String title; // What it was for, e.g., "Grocery", "HDFC Debit"

  @HiveField(4)
  final String type; // 'Expense', 'Income', 'Transfer'
  
  @HiveField(5)
  final String accountId; // The bank/credit card where this occurred

  @HiveField(6)
  final String? categoryId; // The category it belongs to (e.g. food)

  @HiveField(7)
  final String? description; // Optional notes

  @HiveField(8)
  final String status; // 'pending' (intent triggered), 'needs_review' (from notification), 'success' (verified), 'cancelled'

  @HiveField(9)
  final String? rawNotificationText; // For debugging and matching logic

  TransactionModel({
    required this.id,
    required this.amount,
    required this.timestamp,
    required this.title,
    required this.type,
    required this.accountId,
    this.categoryId,
    this.description,
    this.status = 'success',
    this.rawNotificationText,
  });

  TransactionModel copyWith({
    String? id,
    double? amount,
    DateTime? timestamp,
    String? title,
    String? type,
    String? accountId,
    String? categoryId,
    String? description,
    String? status,
    String? rawNotificationText,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      timestamp: timestamp ?? this.timestamp,
      title: title ?? this.title,
      type: type ?? this.type,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      description: description ?? this.description,
      status: status ?? this.status,
      rawNotificationText: rawNotificationText ?? this.rawNotificationText,
    );
  }
} // closing brace
