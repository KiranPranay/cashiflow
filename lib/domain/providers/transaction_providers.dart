import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/data/repositories/hive_transaction_repository.dart';

final transactionRepositoryProvider = Provider((ref) {
  final box = Hive.box<TransactionModel>('transactions_v2');
  return HiveTransactionRepository(box);
});

final transactionsStreamProvider = StreamProvider<List<TransactionModel>>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.watchTransactions();
});
