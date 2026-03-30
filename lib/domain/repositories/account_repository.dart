import 'package:cashi_flow/domain/models/account_model.dart';

abstract class AccountRepository {
  Stream<List<AccountModel>> watchAccounts();
  Future<void> addAccount(AccountModel account);
  Future<void> updateAccount(AccountModel account);
  Future<void> deleteAccount(String id);
  Future<AccountModel?> getAccountById(String id);
}
