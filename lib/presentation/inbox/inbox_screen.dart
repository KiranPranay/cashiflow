import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review Inbox')),
      body: transactionsAsync.when(
        data: (txs) {
          final pending = txs.where((t) => t.status == 'needs_review').toList();
          
          if (pending.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 80, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text('Inbox is clean!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('All automatic payments have been verified.'),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: () => context.pop(), child: const Text('Back to Dashboard')),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final tx = pending[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(tx.title),
                  subtitle: Text('Caught from Notification\n₹${tx.amount.toStringAsFixed(2)}'),
                  trailing: const Icon(Icons.edit),
                  isThreeLine: true,
                  onTap: () => _showReviewDialog(context, ref, tx),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showReviewDialog(BuildContext context, WidgetRef ref, TransactionModel tx) {
    showDialog(context: context, builder: (ctx) => _ReviewDialog(tx: tx));
  }
}

class _ReviewDialog extends ConsumerStatefulWidget {
  final TransactionModel tx;
  const _ReviewDialog({required this.tx});

  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  late TextEditingController _titleCtrl;
  String? _accountId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.tx.title);
  }

  void _confirm() async {
    if (_accountId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select Account and Category')));
      return;
    }

    final repo = ref.read(transactionRepositoryProvider);
    final accRepo = ref.read(accountRepositoryProvider);

    // 1. Update Transaction
    final updatedTx = widget.tx.copyWith(
      title: _titleCtrl.text,
      accountId: _accountId,
      categoryId: _categoryId,
      status: 'success',
    );
    await repo.updateTransaction(updatedTx);

    // 2. Adjust Account Balance
    final account = await accRepo.getAccountById(_accountId!);
    if (account != null) {
      final newBal = widget.tx.type == 'Expense' 
        ? account.balance - widget.tx.amount 
        : account.balance + widget.tx.amount;
      await accRepo.updateAccount(account.copyWith(balance: newBal));
    }

    if (mounted) context.pop();
  }

  void _discard() async {
    final repo = ref.read(transactionRepositoryProvider);
    await repo.deleteTransaction(widget.tx.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    
    final List<AccountModel> accounts = accountsAsync.hasValue ? accountsAsync.value! : [];
    final List<CategoryModel> categories = categoriesAsync.hasValue ? categoriesAsync.value! : [];

    return AlertDialog(
      title: const Text('Review Payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('₹${widget.tx.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Payee / Title'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _accountId,
              items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
              onChanged: (v) => setState(() => _accountId = v),
              decoration: const InputDecoration(labelText: 'Paid From (Account)'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _categoryId,
              items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _categoryId = v),
              decoration: const InputDecoration(labelText: 'Category'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _discard, child: const Text('Discard', style: TextStyle(color: Colors.red))),
        FilledButton(onPressed: _confirm, child: const Text('Verify & Save')),
      ],
    );
  }
}
