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

  NotificationService(this._repo, this._accountRepo, this._settingsRepo);

  void startListening() {
    _subscription?.cancel();
    _subscription = _notifChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _handlePaymentNotification(Map<String, String>.from(event));
        }
      },
      onError: (_) {},
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handlePaymentNotification(Map<String, String> data) async {
    final rawTitle = data['rawTitle'] ?? '';
    final rawText = data['rawText'] ?? '';
    final fallbackAmount = data['amount'];
    final fallbackPayee = data['payee'] ?? 'Unknown Payment';

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
        print("Gemini Parsing Failed: $e");
      }
    }

    // 2. Fallback to Native Regex if Gemini failed or missing
    if (parsedAmount == null) {
      if (fallbackAmount == null) return;
      parsedAmount = double.tryParse(fallbackAmount);
      if (parsedAmount == null) return;
    }

    // 3. Match against pending interactions
    final pending = await _repo.findPendingByAmount(parsedAmount);

    if (pending != null) {
      // It matches an intended transaction: Confirm it and deduct!
      final confirmed = pending.copyWith(
        status: 'success',
        title: parsedPayee != 'Unknown Payment' ? parsedPayee : pending.title,
        description: parsedPayee.isNotEmpty ? 'Payee: $parsedPayee (UPI)' : pending.description,
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
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        amount: parsedAmount,
        timestamp: DateTime.now(),
        title: parsedPayee.isNotEmpty ? 'Payment to $parsedPayee' : 'Unknown Transfer',
        type: 'Expense',
        accountId: '', 
        categoryId: '',
        status: 'needs_review',
        rawNotificationText: "$rawTitle : $rawText",
      );
      await _repo.addTransaction(newTx);
    }
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
