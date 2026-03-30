import 'package:hive_flutter/hive_flutter.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/repositories/account_repository.dart';

class HiveAccountRepository implements AccountRepository {
  final Box<AccountModel> _box;

  HiveAccountRepository(this._box);

  @override
  Stream<List<AccountModel>> watchAccounts() async* {
    yield _box.values.toList();
    yield* _box.watch().map((event) => _box.values.toList());
  }

  @override
  Future<void> addAccount(AccountModel account) async {
    await _box.put(account.id, account);
  }

  @override
  Future<void> updateAccount(AccountModel account) async {
    await _box.put(account.id, account);
  }

  @override
  Future<void> deleteAccount(String id) async {
    await _box.delete(id);
  }

  @override
  Future<AccountModel?> getAccountById(String id) async {
    return _box.get(id);
  }
}
