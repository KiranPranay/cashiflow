import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cashi_flow/core/secrets.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
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

// Single place to swap the Gemini model. Using the cheapest flash-lite tier.
const _kGeminiModel = 'gemini-2.5-flash-lite';

// On-device parsing patterns. These mirror the native Kotlin regex in
// UpiNotificationListenerService.kt so notifications are parsed locally first
// and AI is only a fallback (privacy + cost).
final RegExp _kAmountRe = RegExp(
  r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);
final RegExp _kRefRe = RegExp(
  r'(?:upi\s*ref(?:erence)?(?:\s*(?:no|number|id))?|ref(?:erence)?\s*(?:no\.?|number|id)?|utr|txn\s*(?:id|no)?|transaction\s*id)\s*[:#-]?\s*([a-z0-9]{6,})',
  caseSensitive: false,
);
final RegExp _kPayeeRe = RegExp(
  r'(?:to|from|paid)\s+(.+?)(?:\s+(?:is\s+)?(?:successful|completed|done)|[.!]|$)',
  caseSensitive: false,
);

class NotificationService {
  final TransactionRepository _repo;
  final AccountRepository _accountRepo;
  final CategoryRepository _categoryRepo;
  final UserSettingsRepository _settingsRepo;
  StreamSubscription? _subscription;
  bool _isProcessingQueue = false;

  NotificationService(this._repo, this._accountRepo, this._categoryRepo, this._settingsRepo);

  /// Resolves which Gemini API key to use:
  ///  (a) the embedded key if it's been baked in (non-empty, not placeholder),
  ///  otherwise (b) the user's own key from settings. Returns null if neither.
  String? _resolveGeminiKey(UserSettingsModel? settings) {
    if (isEmbeddedGeminiKeyConfigured) return kEmbeddedGeminiApiKey;
    final userKey = settings?.geminiApiKey;
    if (userKey != null && userKey.isNotEmpty) return userKey;
    return null;
  }

  /// On-device parse of a notification using regex only (no network, no AI).
  /// Mirrors the native Kotlin patterns. Returns null when no usable amount can
  /// be found, which signals the caller it may fall back to Gemini.
  _LocalParseResult? _parseLocally(Map<String, String> data) {
    final rawTitle = data['rawTitle'] ?? '';
    final rawText = data['rawText'] ?? '';
    final combined = '$rawTitle $rawText';
    final lower = combined.toLowerCase();

    // Amount: regex over the raw text first, then the native pre-parsed amount.
    double? amount;
    final m = _kAmountRe.firstMatch(combined);
    if (m != null) amount = double.tryParse(m.group(1)!.replaceAll(',', ''));
    amount ??= double.tryParse(data['amount'] ?? '');
    if (amount == null) return null; // no amount => caller may use AI fallback.

    // Type: credited/received/added => Income; debited/paid/etc => Expense.
    const incomeWords = ['credited', 'received', 'added'];
    const expenseWords = [
      'debited', 'paid', 'sent', 'spent', 'transferred', 'withdrawn', 'purchase'
    ];
    final isIncome = incomeWords.any(lower.contains);
    final isExpense = expenseWords.any(lower.contains);
    String type;
    if (isIncome && !isExpense) {
      type = 'Income';
    } else if (isExpense) {
      type = 'Expense';
    } else {
      // No directional keyword: trust the native-provided type, else Expense.
      type = data['type'] == 'Income' ? 'Income' : 'Expense';
    }

    // Reference: regex, else the native-provided reference.
    String? reference = _kRefRe.firstMatch(combined)?.group(1);
    if (reference == null || reference.isEmpty) {
      final nativeRef = data['reference'];
      reference = (nativeRef != null && nativeRef.isNotEmpty) ? nativeRef : null;
    }

    // Payee: regex, else the native-provided payee.
    String payee = _kPayeeRe.firstMatch(combined)?.group(1)?.trim() ?? '';
    if (payee.isEmpty) payee = (data['payee'] ?? '').trim();

    return _LocalParseResult(
      amount: amount,
      type: type,
      payee: payee,
      reference: reference,
    );
  }

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
    final fallbackPayee = data['payee'] ?? 'Unknown Payment';
    final messageId = data['messageId'];

    double? parsedAmount;
    String parsedPayee = fallbackPayee;
    String parsedType = 'Expense';
    String parsedAccountId = 'unknown';
    String parsedCategoryId = 'unknown';
    String? parsedReference;

    final settings = await _settingsRepo.watchSettings().first;

    // Use the real notification time (postedAt epoch millis) so an item synced
    // hours later is logged at its true time; fall back to now() if missing.
    final postedAtMs = int.tryParse(data['postedAt'] ?? '');
    final txTimestamp = postedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(postedAtMs)
        : DateTime.now();

    // === Local-first parsing (privacy + cost) ===
    // Parse on-device with regex first; the common case never touches AI.
    final local = _parseLocally(data);
    if (local != null) {
      parsedAmount = local.amount;
      parsedType = local.type;
      if (local.payee.isNotEmpty) parsedPayee = local.payee;
      parsedReference = local.reference;
      // Local parse can't map a specific account/category; left as 'unknown'.
    }

    // === AI fallback === only when local parsing found NO amount and a key exists.
    if (parsedAmount == null) {
      final geminiKey = _resolveGeminiKey(settings);
      if (geminiKey != null && geminiKey.isNotEmpty) {
        try {
        final accounts = await _accountRepo.watchAccounts().first;
        final categories = await _categoryRepo.watchCategories().first;
        
        final accountsListStr = accounts.map((a) => '{"id": "${a.id}", "name": "${a.name}"}').join(',\\n');
        final categoriesListStr = categories.map((c) => '{"id": "${c.id}", "name": "${c.name}"}').join(',\\n');

        final model = GenerativeModel(
          model: _kGeminiModel,
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
          // Treated as a parse failure (handled just below). We don't retry
          // forever; the queue item is cleared in the next block.
          print("Gemini Parsing Failed: $e");
        }
      }
    }

    if (parsedAmount == null) {
      // Both local and AI parsing failed. Return true so the queue item is
      // cleared (not retried forever), but log it for debugging.
      print("Skipping notification: no amount via local or AI. raw='$rawTitle : $rawText'");
      return true;
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
        timestamp: txTimestamp,
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

/// Result of on-device (regex) parsing of a payment notification. A non-null
/// instance means parsing succeeded locally and Gemini was NOT needed.
class _LocalParseResult {
  final double amount;
  final String type; // 'Expense' | 'Income'
  final String payee;
  final String? reference;

  _LocalParseResult({
    required this.amount,
    required this.type,
    required this.payee,
    this.reference,
  });
}
