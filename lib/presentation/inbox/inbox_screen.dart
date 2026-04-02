import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/presentation/shared/transaction_editor_dialog.dart';

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
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: tx.type == 'Transfer'
                      ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5)
                      : (tx.type == 'Expense' 
                          ? Theme.of(context).colorScheme.error.withValues(alpha: 0.5) 
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                    width: 1
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(
                    tx.type == 'Transfer' ? Icons.swap_horiz : (tx.type == 'Expense' ? Icons.call_made_rounded : Icons.call_received_rounded),
                    color: tx.type == 'Transfer'
                      ? Theme.of(context).colorScheme.secondary
                      : (tx.type == 'Expense' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(tx.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${tx.type} • Caught from Notification\n₹${tx.amount.toStringAsFixed(2)}'),
                  trailing: const Icon(Icons.edit),
                  isThreeLine: true,
                  onTap: () => showDialog(
                    context: context, 
                    builder: (ctx) => TransactionEditorDialog(tx: tx)
                  ),
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
}
