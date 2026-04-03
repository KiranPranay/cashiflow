import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/repositories/transaction_repository.dart';
import 'package:cashi_flow/domain/repositories/account_repository.dart';
import 'package:cashi_flow/domain/repositories/category_repository.dart';
import 'package:cashi_flow/domain/repositories/user_settings_repository.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';
import 'package:cashi_flow/domain/providers/user_settings_providers.dart';

const _upiChannel = MethodChannel('com.weberq.cashiflow/upi');
const _notifChannel = EventChannel('com.weberq.cashiflow/notifications');

class NotificationService {
  final TransactionRepository _repo;
  final AccountRepository _accountRepo;
  final CategoryRepository _categoryRepo;
  final UserSettingsRepository _settingsRepo;
  StreamSubscription? _subscription;
  bool _isProcessingQueue = false;

  NotificationService(this._repo, this._accountRepo, this._categoryRepo, this._settingsRepo);

  void startListening() {
    _syncOfflineQueue();
    _subscription?.cancel();
    _subscription = _notifChannel.receiveBroadcastStream().listen(
      (event) async {
        if (event is Map) {
          final data = event.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          await _processSingleNotification(data);
        }
      },
      onError: (_) {},
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _syncOfflineQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final List<dynamic>? pendingRaw = await _upiChannel.invokeMethod('getPendingNotifications');
      if (pendingRaw != null && pendingRaw.isNotEmpty) {
        print("Found ${pendingRaw.length} offline queued notifications. Syncing now...");
        
        for (final rawItem in pendingRaw) {
          if (rawItem is Map) {
            final data = rawItem.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
            final messageId = data['messageId'];
            
            final success = await _processSingleNotification(data);
            
            if (success && messageId != null) {
               await _upiChannel.invokeMethod('removeQueuedNotification', {'id': messageId});
               print("Removed synced notification $messageId from Native Queue.");
            }
            
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    } catch (e) {
      print("Offline Sync Engine Error: $e");
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<AccountModel> _getOrCreateUnknownAccount() async {
    final accounts = await _accountRepo.watchAccounts().first;
    try {
      return accounts.firstWhere((a) => a.id == 'unknown_bank' || a.name == 'Unknown Bank');
    } catch (_) {
      final unknown = AccountModel(id: 'unknown_bank', name: 'Unknown Bank', balance: 0, type: 'Bank');
      await _accountRepo.addAccount(unknown);
      return unknown;
    }
  }

  Future<CategoryModel> _getOrCreateUnknownCategory() async {
    final categories = await _categoryRepo.watchCategories().first;
    try {
      return categories.firstWhere((c) => c.id == 'unknown_category' || c.name == 'Unknown Category');
    } catch (_) {
      final unknown = CategoryModel(id: 'unknown_category', name: 'Unknown Category', type: 'Expense', iconName: 'help_outline', colorHex: 0xFF9E9E9E);
      await _categoryRepo.addCategory(unknown);
      return unknown;
    }
  }

  Future<bool> _processSingleNotification(Map<String, String> data) async {
    final rawTitle = data['rawTitle'] ?? '';
    final rawText = data['rawText'] ?? '';
    final fallbackAmount = data['amount'];
    final fallbackPayee = data['payee'] ?? 'Unknown Payment';
    final messageId = data['messageId'];

    double? parsedAmount;
    String parsedPayee = fallbackPayee;
    String parsedType = 'Expense';
    String parsedAccountId = 'unknown';
    String parsedCategoryId = 'unknown';
    String? parsedReference;

    final settings = await _settingsRepo.watchSettings().first;
    final geminiKey = settings?.geminiApiKey;

    if (geminiKey != null && geminiKey.isNotEmpty) {
      try {
        final accounts = await _accountRepo.watchAccounts().first;
        final categories = await _categoryRepo.watchCategories().first;
        
        final accountsListStr = accounts.map((a) => '{"id": "${a.id}", "name": "${a.name}"}').join(',\\n');
        final categoriesListStr = categories.map((c) => '{"id": "${c.id}", "name": "${c.name}"}').join(',\\n');

        final model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: geminiKey,
        );
        final prompt = '''
You are a banking notification parser. Extract details strictly from the following notification text. 
Return ONLY a strictly valid JSON object. No markdown. No backticks.

Available Accounts:
[\n$accountsListStr\n]

Available Categories:
[\n$categoriesListStr\n]

Schema: {"amount": double, "payee": "string", "type": "Expense" | "Income", "accountId": "string", "categoryId": "string", "referenceNumber": "string"}
- For "type", determine if money was deducted ("Expense") or credited ("Income").
- For "accountId", choose the BEST matching account id from Available Accounts. If unsure or not in the list, use specifically the string "unknown".
- For "categoryId", choose the BEST matching category id from Available Categories. If unsure or not in the list, use specifically the string "unknown".
- For "payee", string representing the recipient or sender.
- For "referenceNumber", extract any specific transaction tracking code, UTR, or UPI Ref number. If completely absent, provide empty string "".

Notification Title: $rawTitle
Notification Text: $rawText
        ''';

        final response = await model.generateContent([Content.text(prompt)]);
        final textResponse = response.text?.trim() ?? '';
        final cleanJson = textResponse.replaceAll('```json', '').replaceAll('```', '').trim();
        final Map<String, dynamic> jsonMap = jsonDecode(cleanJson);

        if (jsonMap.containsKey('amount')) parsedAmount = (jsonMap['amount'] as num).toDouble();
        if (jsonMap.containsKey('payee')) parsedPayee = jsonMap['payee'].toString();
        if (jsonMap.containsKey('type')) {
           final t = jsonMap['type'].toString();
           if (t == 'Expense' || t == 'Income') parsedType = t;
        }
        if (jsonMap.containsKey('accountId')) parsedAccountId = jsonMap['accountId'].toString();
        if (jsonMap.containsKey('categoryId')) parsedCategoryId = jsonMap['categoryId'].toString();
        if (jsonMap.containsKey('referenceNumber') && jsonMap['referenceNumber'].toString().isNotEmpty) {
           parsedReference = jsonMap['referenceNumber'].toString();
        }
      } catch (e) {
        print("Gemini Parsing Failed: $e");
        return false; 
      }
    }

    if (parsedAmount == null) {
      if (fallbackAmount == null || fallbackAmount.isEmpty) return true; 
      parsedAmount = double.tryParse(fallbackAmount);
      if (parsedAmount == null) return true; 
    }

    // Resolve "unknown" fallbacks
    if (parsedAccountId == 'unknown') {
      final unkAcc = await _getOrCreateUnknownAccount();
      parsedAccountId = unkAcc.id;
    }
    if (parsedCategoryId == 'unknown') {
      final unkCat = await _getOrCreateUnknownCategory();
      parsedCategoryId = unkCat.id;
    }

    if (parsedReference != null && parsedReference.isNotEmpty) {
      final existingTx = await _repo.findByReferenceNumber(parsedReference);
      if (existingTx != null) {
         print("Duplicate Catch! Transaction matched existing Ref NO: $parsedReference");
         return true; // we return true so the queue marks it synced/cleared correctly without injecting duplicates.
      }
    }

    final pending = await _repo.findPendingByAmount(parsedAmount);

    if (pending != null) {
      final confirmed = pending.copyWith(
        status: 'success',
        title: parsedPayee != 'Unknown Payment' ? parsedPayee : pending.title,
        description: parsedPayee.isNotEmpty ? 'Payee: $parsedPayee (UPI via Offline Sync)' : pending.description,
        type: parsedType != 'Expense' && parsedType != 'Income' ? pending.type : parsedType,
        accountId: parsedAccountId != 'unknown' ? parsedAccountId : pending.accountId,
        categoryId: parsedCategoryId != 'unknown' ? parsedCategoryId : pending.categoryId,
        referenceNumber: parsedReference ?? pending.referenceNumber,
      );
      await _repo.updateTransaction(confirmed);

      final account = await _accountRepo.getAccountById(confirmed.accountId);
      if (account != null) {
        final double newBal = confirmed.type == 'Expense' 
            ? account.balance - confirmed.amount 
            : account.balance + confirmed.amount;
        await _accountRepo.updateAccount(account.copyWith(balance: newBal));
      }

    } else {
      final newTx = TransactionModel(
        id: messageId ?? DateTime.now().millisecondsSinceEpoch.toString(), 
        amount: parsedAmount,
        timestamp: DateTime.now(),
        title: parsedPayee.isNotEmpty ? 'Payment to $parsedPayee' : 'Unknown Transfer',
        type: parsedType,
        accountId: parsedAccountId, 
        categoryId: parsedCategoryId,
        referenceNumber: parsedReference,
        status: 'needs_review',
        rawNotificationText: "$rawTitle : $rawText",
      );
      
      try {
        await _repo.addTransaction(newTx);
      } catch (e) {
        print("Failed to save synced transaction to Hive: $e");
        return false; 
      }
    }

    return true; 
  }

  static Future<bool> isPermissionGranted() async {
    try {
      final result = await _upiChannel.invokeMethod<bool>('isNotificationAccessGranted');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _upiChannel.invokeMethod('requestNotificationAccess');
    } catch (_) {}
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  final accountRepo = ref.watch(accountRepositoryProvider);
  final categoryRepo = ref.watch(categoryRepositoryProvider);
  final settingsRepo = ref.watch(userSettingsRepositoryProvider);
  
  final service = NotificationService(repo, accountRepo, categoryRepo, settingsRepo);
  service.startListening();
  ref.onDispose(() => service.dispose());
  return service;
});
