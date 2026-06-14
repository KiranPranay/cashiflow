import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';

class BackupService {
  // BUGFIX(2): Robustly coerce a JSON value into an int regardless of whether
  // it arrives as an int, a double, or a numeric String. Older/newer backups
  // may encode colorHex either way; the previous `int.tryParse(x.toString())`
  // could silently yield 0 (an invisible/transparent color). [fallback] is
  // returned for null or unparseable values.
  int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? fallback;
    }
    return fallback;
  }

  // BUGFIX(2): Robustly coerce a JSON value into a double (int/double/String/
  // null all handled) so creditLimit/balance never throw on an unexpected type.
  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  // BUGFIX(3): Convert a JSON value to a String while preserving genuine nulls
  // as null, so an absent/null field is never stored as the literal "null".
  String? _asStringOrNull(dynamic value) => value?.toString();

  Future<bool> exportBackup() async {
    try {
      final txBox = Hive.box<TransactionModel>('transactions_v2');
      final accBox = Hive.box<AccountModel>('accounts');
      final catBox = Hive.box<CategoryModel>('categories');
      final setBox = Hive.box<UserSettingsModel>('user_settings');

      final txList = txBox.values.map((t) => {
        'id': t.id,
        'amount': t.amount,
        'timestamp': t.timestamp.toIso8601String(),
        'title': t.title,
        'type': t.type,
        'accountId': t.accountId,
        'categoryId': t.categoryId,
        'destinationAccountId': t.destinationAccountId,
        'referenceNumber': t.referenceNumber,
        'description': t.description,
        'status': t.status,
        'rawNotificationText': t.rawNotificationText,
      }).toList();

      final accList = accBox.values.map((a) => {
        'id': a.id,
        'name': a.name,
        'type': a.type,
        'balance': a.balance,
        'creditLimit': a.creditLimit,
        'iconName': a.iconName,
        // BUGFIX(2): emit colorHex as a raw int so it round-trips via _asInt().
        'colorHex': a.colorHex,
      }).toList();

      final catList = catBox.values.map((c) => {
        'id': c.id,
        'name': c.name,
        'type': c.type,
        'iconName': c.iconName,
        // BUGFIX(2): emit colorHex as a raw int so it round-trips via _asInt().
        'colorHex': c.colorHex,
      }).toList();

      final setObj = setBox.get('settings');
      final settingsMap = setObj != null ? {
        'onboardingCompleted': setObj.onboardingCompleted,
        'expectedIncomes': setObj.expectedIncomes,
        'geminiApiKey': setObj.geminiApiKey,
      } : null;

      final backupData = {
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'transactions': txList,
        'accounts': accList,
        'categories': catList,
        'settings': settingsMap,
      };

      final jsonString = jsonEncode(backupData);
      String? outputDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Backup Folder',
      );

      if (outputDir != null) {
        final path = '$outputDir/cashi_flow_backup_${DateTime.now().millisecondsSinceEpoch}.json';
        final file = File(path);
        await file.writeAsString(jsonString);
        return true;
      }
      return false; // User canceled
    } catch (e) {
      print("Export Error: $e");
      return false;
    }
  }

  Future<bool> importBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Backup File',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final payload = jsonDecode(jsonString);

        if (payload['version'] == null) {
          throw Exception("Invalid backup file structure.");
        }

        final txBox = Hive.box<TransactionModel>('transactions_v2');
        final accBox = Hive.box<AccountModel>('accounts');
        final catBox = Hive.box<CategoryModel>('categories');
        final setBox = Hive.box<UserSettingsModel>('user_settings');

        // Clear existing data safely
        await txBox.clear();
        await accBox.clear();
        await catBox.clear();
        await setBox.clear();

        // 1. Settings
        if (payload['settings'] != null) {
          final sm = payload['settings'];
          await setBox.put('settings', UserSettingsModel(
            onboardingCompleted: sm['onboardingCompleted'] ?? true,
            expectedIncomes: (sm['expectedIncomes'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ?? {},
            geminiApiKey: sm['geminiApiKey'],
          ));
        }

        // 2. Categories
        if (payload['categories'] != null) {
          final cats = (payload['categories'] as List).map((c) => CategoryModel(
            id: c['id'].toString(),
            name: c['name'].toString(),
            type: c['type'].toString(),
            iconName: c['iconName'].toString(),
            // BUGFIX(2): parse colorHex robustly; fall back to the model's
            // default grey (0xFFAAAAAA) rather than 0 (invisible) on failure.
            colorHex: _asInt(c['colorHex'], fallback: 0xFFAAAAAA),
          )).toList();
          for (var c in cats) {
            await catBox.put(c.id, c);
          }
        }

        // 3. Accounts
        if (payload['accounts'] != null) {
          final accs = (payload['accounts'] as List).map((a) => AccountModel(
            id: a['id'].toString(),
            name: a['name'].toString(),
            type: a['type'].toString(),
            // BUGFIX(2): coerce numeric fields safely (int/double/String/null)
            // so an unexpected JSON type can't throw and abort the whole import.
            balance: _asDouble(a['balance']),
            creditLimit: _asDouble(a['creditLimit']),
            iconName: a['iconName'].toString(),
            colorHex: _asInt(a['colorHex'], fallback: 0xFFAAAAAA),
          )).toList();
          for (var a in accs) {
            await accBox.put(a.id, a);
          }
        }

        // 4. Transactions
        if (payload['transactions'] != null) {
          final txs = (payload['transactions'] as List).map((t) => TransactionModel(
            id: t['id'].toString(),
            amount: (t['amount'] as num).toDouble(),
            timestamp: DateTime.parse(t['timestamp'].toString()),
            title: t['title'].toString(),
            type: t['type'].toString(),
            accountId: t['accountId'].toString(),
            categoryId: _asStringOrNull(t['categoryId']),
            // BUGFIX(3): preserve genuine nulls so optional fields are never
            // stored as the literal string "null".
            destinationAccountId: _asStringOrNull(t['destinationAccountId']),
            referenceNumber: _asStringOrNull(t['referenceNumber']),
            description: _asStringOrNull(t['description']),
            status: t['status'].toString(),
            rawNotificationText: _asStringOrNull(t['rawNotificationText']),
          )).toList();
          for (var tx in txs) {
            await txBox.put(tx.id, tx);
          }
        }

        return true;
      }
      return false; // User canceled
    } catch (e) {
      print("Import Error: $e");
      return false;
    }
  }
}

final backupServiceProvider = Provider<BackupService>((ref) => BackupService());
