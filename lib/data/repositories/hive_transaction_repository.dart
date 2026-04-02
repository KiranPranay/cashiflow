import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/repositories/transaction_repository.dart';

class HiveTransactionRepository implements TransactionRepository {
  final Box<TransactionModel> _transactionBox;

  HiveTransactionRepository(this._transactionBox);

  @override
  Future<void> addTransaction(TransactionModel transaction) async {
    await _transactionBox.put(transaction.id, transaction);
  }

  @override
  Future<void> updateTransaction(TransactionModel transaction) async {
    await _transactionBox.put(transaction.id, transaction);
  }

  @override
  Future<void> deleteTransaction(String id) async {
    await _transactionBox.delete(id);
  }

  @override
  Future<List<TransactionModel>> getAllTransactions() async {
    final list = _transactionBox.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  @override
  Stream<List<TransactionModel>> watchTransactions() async* {
    final initialList = _transactionBox.values.toList();
    initialList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    yield initialList;

    yield* _transactionBox.watch().map((event) {
      final list = _transactionBox.values.toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    });
  }

  @override
  Future<void> clearTransactions() async {
    await _transactionBox.clear();
  }

  @override
  Future<TransactionModel?> findPendingByAmount(double amount, {Duration window = const Duration(minutes: 5)}) async {
    final now = DateTime.now();
    try {
      return _transactionBox.values.firstWhere((tx) {
        if (tx.status != 'needs_review') return false;
        if ((tx.amount - amount).abs() > 0.01) return false;
        
        final diff = now.difference(tx.timestamp).abs();
        return diff <= window;
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TransactionModel?> findByReferenceNumber(String refNo) async {
    try {
      if (refNo.trim().isEmpty) return null;
      return _transactionBox.values.firstWhere((tx) => tx.referenceNumber?.toLowerCase() == refNo.trim().toLowerCase());
    } catch (_) {
      return null;
    }
  }
}
