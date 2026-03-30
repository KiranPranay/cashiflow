import 'package:cashi_flow/domain/models/transaction_model.dart';

abstract class TransactionRepository {
  Future<void> addTransaction(TransactionModel transaction);
  Future<void> updateTransaction(TransactionModel transaction);
  Future<List<TransactionModel>> getAllTransactions();
  Future<void> deleteTransaction(String id);
  Future<void> clearTransactions();
  Stream<List<TransactionModel>> watchTransactions();
  Future<TransactionModel?> findPendingByAmount(double amount, {Duration window = const Duration(minutes: 5)});
}
