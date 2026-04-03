import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';

Future<void> showAddAccountDialog(BuildContext context, WidgetRef ref) async {
  final nameCtrl = TextEditingController();
  final balCtrl = TextEditingController();
  String type = 'Bank';
  
  await showDialog(
    context: context, 
    builder: (ctx) => StatefulBuilder(
      builder: (context, setStateBuilder) => AlertDialog(
        title: const Text('Add Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: type,
              items: ['Bank', 'Credit', 'Wallet', 'Cash'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setStateBuilder(() => type = v!),
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Account Name')),
            TextField(controller: balCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current Balance / Bill')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final bal = double.tryParse(balCtrl.text) ?? 0;
            if (nameCtrl.text.isNotEmpty) {
              ref.read(accountRepositoryProvider).addAccount(AccountModel(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text,
                type: type,
                balance: type == 'Credit' ? -bal.abs() : bal,
                creditLimit: type == 'Credit' ? bal * 2 : 0,
                iconName: 'account_balance',
              ));
              Navigator.pop(ctx);
            }
          }, child: const Text('Add')),
        ],
      )
    )
  );
}

Future<void> showAddCategoryDialog(BuildContext context, WidgetRef ref, {String? defaultType}) async {
  final nameCtrl = TextEditingController();
  String type = defaultType ?? 'Expense';
  
  await showDialog(
    context: context, 
    builder: (ctx) => StatefulBuilder(
      builder: (context, setStateBuilder) => AlertDialog(
        title: const Text('Add Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: type,
              items: ['Expense', 'Income', 'Transfer'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setStateBuilder(() => type = v!),
              decoration: const InputDecoration(labelText: 'Type'),
            ),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Category Name')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (nameCtrl.text.isNotEmpty) {
              ref.read(categoryRepositoryProvider).addCategory(CategoryModel(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text,
                type: type,
                iconName: 'label',
                colorHex: 0xFF00E676,
              ));
              Navigator.pop(ctx);
            }
          }, child: const Text('Add')),
        ],
      )
    )
  );
}
