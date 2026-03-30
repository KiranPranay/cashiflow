import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/data/repositories/hive_account_repository.dart';

final accountRepositoryProvider = Provider((ref) {
  final box = Hive.box<AccountModel>('accounts');
  return HiveAccountRepository(box);
});

final accountsStreamProvider = StreamProvider<List<AccountModel>>((ref) {
  final repo = ref.watch(accountRepositoryProvider);
  return repo.watchAccounts();
});
