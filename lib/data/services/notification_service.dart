import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/repositories/transaction_repository.dart';
import 'package:cashi_flow/domain/repositories/account_repository.dart';
import 'package:cashi_flow/domain/repositories/user_settings_repository.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/user_settings_providers.dart';

const _upiChannel = MethodChannel('com.cashi_flow/upi');
const _notifChannel = EventChannel('com.cashi_flow/notifications');

class NotificationService {
  final TransactionRepository _repo;
  final AccountRepository _accountRepo;
  final UserSettingsRepository _settingsRepo;
  StreamSubscription? _subscription;
  bool _isProcessingQueue = false;

  NotificationService(this._repo, this._accountRepo, this._settingsRepo);

  void startListening() {
    // 1. Fire up the offline queue syncer immediately on boot
    _syncOfflineQueue();

    // 2. Listen to live events if the app happens to be open
    _subscription?.cancel();
    _subscription = _notifChannel.receiveBroadcastStream().listen(
      (event) async {
        if (event is Map) {
          final data = event.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
          // Add to processing loop rather than concurrent executing to prevent race conditions
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
            
            // Process sequentially to prevent Gemini Rate Limits (HTTP 429)
            final success = await _processSingleNotification(data);
            
            // If processing was purely successful (AI parsed, Hive saved), tell Android to nuke it from SharedPreferences
            if (success && messageId != null) {
               await _upiChannel.invokeMethod('removeQueuedNotification', {'id': messageId});
               print("Removed synced notification $messageId from Native Queue.");
            }
            
            // Respect API limits
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

  /// Returns true if the notification was completely processed and stored in the ledger.
  /// Returns false if it failed due to Gemini Exception (no internet) so the Queue keeps it.
  Future<bool> _processSingleNotification(Map<String, String> data) async {
    final rawTitle = data['rawTitle'] ?? '';
    final rawText = data['rawText'] ?? '';
    final fallbackAmount = data['amount'];
    final fallbackPayee = data['payee'] ?? 'Unknown Payment';
    final messageId = data['messageId'];

    // If we've already synced this transaction via a previous pass or live-stream, 
    // it will have a matching rawText signature in Hive. We can do a quick de-dupe guard.
    // However, SharedPreferences removal mitigates this natively.

    double? parsedAmount;
    String parsedPayee = fallbackPayee;

    // 1. Check for Gemini Key and Attempt AI Parsing
    final settings = await _settingsRepo.watchSettings().first;
    final geminiKey = settings?.geminiApiKey;

    if (geminiKey != null && geminiKey.isNotEmpty) {
      try {
        final model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: geminiKey,
        );
        final prompt = '''
You are a banking notification parser. Extract the payment amount and payee exactly from the following notification text. 
Return ONLY a strictly valid JSON object. No markdown. No backticks.
Schema: {"amount": double, "payee": "string"}
Notification Title: $rawTitle
Notification Text: $rawText
        ''';

        final response = await model.generateContent([Content.text(prompt)]);
        final textResponse = response.text?.trim() ?? '';
        final cleanJson = textResponse.replaceAll('```json', '').replaceAll('```', '').trim();
        final Map<String, dynamic> jsonMap = jsonDecode(cleanJson);

        if (jsonMap.containsKey('amount')) {
          parsedAmount = (jsonMap['amount'] as num).toDouble();
        }
        if (jsonMap.containsKey('payee')) {
          parsedPayee = jsonMap['payee'].toString();
        }
      } catch (e) {
        // NO INTERNET, API LIMIT, OR SERVICE UNAVAILABLE
        print("Gemini Parsing Failed: $e");
        // Returning FALSE indicates the Native Queue should NOT delete this message yet!
        return false; 
      }
    }

    // 2. Fallback to Native Regex if Gemini wasn't configured or failed mapping
    if (parsedAmount == null) {
      if (fallbackAmount == null || fallbackAmount.isEmpty) {
        // Completely useless notification, mark as processed so Native queue deletes it
        return true; 
      }
      parsedAmount = double.tryParse(fallbackAmount);
      if (parsedAmount == null) return true; // Malformed fallback
    }

    // 3. Match against pending interactions
    final pending = await _repo.findPendingByAmount(parsedAmount);

    if (pending != null) {
      // It matches an intended transaction: Confirm it and deduct!
      final confirmed = pending.copyWith(
        status: 'success',
        title: parsedPayee != 'Unknown Payment' ? parsedPayee : pending.title,
        description: parsedPayee.isNotEmpty ? 'Payee: $parsedPayee (UPI via Offline Sync)' : pending.description,
      );
      await _repo.updateTransaction(confirmed);

      // Deduct account balance natively
      final account = await _accountRepo.getAccountById(confirmed.accountId);
      if (account != null) {
        final double newBal = confirmed.type == 'Expense' 
            ? account.balance - confirmed.amount 
            : account.balance + confirmed.amount;
        await _accountRepo.updateAccount(account.copyWith(balance: newBal));
      }

    } else {
      // Unplanned transaction - send to Needs Review inbox
      final newTx = TransactionModel(
        id: messageId ?? DateTime.now().millisecondsSinceEpoch.toString(), // Use native ID to prevent exact duplicates naturally
        amount: parsedAmount,
        timestamp: DateTime.now(),
        title: parsedPayee.isNotEmpty ? 'Payment to $parsedPayee' : 'Unknown Transfer',
        type: 'Expense',
        accountId: '', 
        categoryId: '',
        status: 'needs_review',
        rawNotificationText: "$rawTitle : $rawText",
      );
      
      // Attempt to save to Hive. If it fails, we shouldn't clear the queue.
      try {
        await _repo.addTransaction(newTx);
      } catch (e) {
        print("Failed to save synced transaction to Hive: $e");
        return false; // Leave in native queue
      }
    }

    // If we reach here, Ledger successfully synced data!
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
  final settingsRepo = ref.watch(userSettingsRepositoryProvider);
  
  final service = NotificationService(repo, accountRepo, settingsRepo);
  service.startListening();
  ref.onDispose(() => service.dispose());
  return service;
});
