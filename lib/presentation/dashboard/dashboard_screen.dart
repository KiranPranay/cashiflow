import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/user_settings_providers.dart';
import 'package:cashi_flow/data/services/notification_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    // Eagerly read the notification service to keep it alive
    ref.watch(notificationServiceProvider);

    final accountsAsync = ref.watch(accountsStreamProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final settingsAsync = ref.watch(userSettingsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashi Flow', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add_transaction'),
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
      ),
      body: CustomScrollView(
        slivers: [
          // Global Net Worth & Savings
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: _buildHeaderDash(accountsAsync, transactionsAsync, settingsAsync),
            ),
          ),
          
          // Accounts Overview
          SliverToBoxAdapter(
            child: _buildAccountsSection(accountsAsync),
          ),
          
          // Inbox Alerts
          SliverToBoxAdapter(
            child: _buildInboxAlert(transactionsAsync),
          ),

          // Recent Activity
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          _buildRecentTransactions(transactionsAsync),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildHeaderDash(
    AsyncValue<List<AccountModel>> accountsAsync, 
    AsyncValue<List<TransactionModel>> transactionsAsync,
    AsyncValue<UserSettingsModel?> settingsAsync,
  ) {
    return accountsAsync.when(
      data: (accounts) {
        final netWorth = accounts.fold<double>(0, (sum, acc) => sum + acc.balance);
        
        double currentMonthExpenses = 0;
        transactionsAsync.whenData((txs) {
          final now = DateTime.now();
          currentMonthExpenses = txs.where((t) => 
            t.type == 'Expense' && 
            t.status == 'success' && 
            t.timestamp.month == now.month && 
            t.timestamp.year == now.year
          ).fold(0.0, (sum, i) => sum + i.amount);
        });

        double expectedIncome = 0;
        settingsAsync.whenData((s) {
          if (s != null && s.expectedIncomes.isNotEmpty) {
            expectedIncome = s.expectedIncomes.values.fold<double>(0.0, (sum, amt) => sum + amt);
          }
        });
        
        double projectedSavings = expectedIncome - currentMonthExpenses;

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Total Liquid Balance', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('₹${netWorth.toStringAsFixed(2)}', style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer, 
                    fontSize: 40, fontWeight: FontWeight.bold,
                  )),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expected Savings', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7))),
                          Text('₹${projectedSavings.toStringAsFixed(0)}', style: TextStyle(
                            color: projectedSavings >= 0 ? Colors.green.shade800 : Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold, fontSize: 16,
                          )),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Target Income', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7))),
                          Text('₹${expectedIncome.toStringAsFixed(0)}', style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold, fontSize: 16,
                          )),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Text('Error: $e'),
    );
  }

  Widget _buildAccountsSection(AsyncValue<List<AccountModel>> accountsAsync) {
    return accountsAsync.when(
      data: (accounts) {
        if (accounts.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24.0, right: 24, top: 24, bottom: 12),
              child: Text(
                'Accounts & Cards',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: accounts.length + 1,
                itemBuilder: (context, index) {
                  if (index == accounts.length) {
                    return _buildAddAccountCard();
                  }
                  return _buildAccountCard(accounts[index]);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildAccountCard(AccountModel acc) {
    return Container(
      width: 150,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(acc.type == 'Credit' ? Icons.credit_card : Icons.account_balance, 
            color: Theme.of(context).colorScheme.primary),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(acc.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '₹${acc.balance.abs().toStringAsFixed(0)}', 
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 18,
                  color: acc.balance < 0 ? Theme.of(context).colorScheme.error : null,
                )
              ),
              if (acc.type == 'Credit')
                Text('Limit: ₹${acc.creditLimit.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAddAccountCard() {
    return InkWell(
      onTap: () {
        // Future route to add account directly via dialog or page
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, style: BorderStyle.solid),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 36),
              SizedBox(height: 8),
              Text('Add Account', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInboxAlert(AsyncValue<List<TransactionModel>> transactionsAsync) {
    return transactionsAsync.when(
      data: (txs) {
        final pendingCount = txs.where((t) => t.status == 'needs_review').length;
        if (pendingCount == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
          child: InkWell(
            onTap: () => context.push('/inbox'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_unread, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You have $pendingCount transaction(s) needing review from notifications.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onErrorContainer),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecentTransactions(AsyncValue<List<TransactionModel>> transactionsAsync) {
    return transactionsAsync.when(
      data: (txs) {
        final regularTxs = txs.where((t) => t.status != 'needs_review').toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        final recent = regularTxs.take(10).toList();

        if (recent.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No recent activity', style: TextStyle(color: Colors.grey)),
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final tx = recent[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: tx.type == 'Expense' 
                    ? Theme.of(context).colorScheme.errorContainer 
                    : Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    tx.type == 'Expense' ? Icons.arrow_outward : Icons.south_west,
                    color: tx.type == 'Expense' 
                      ? Theme.of(context).colorScheme.onErrorContainer 
                      : Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(tx.title.isNotEmpty ? tx.title : 'Unknown Payment', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${tx.timestamp.day}/${tx.timestamp.month}/${tx.timestamp.year} • ${tx.type}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  '₹${tx.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: tx.type == 'Expense' ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              );
            },
            childCount: recent.length,
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
      error: (error, stack) => SliverToBoxAdapter(child: Center(child: Text('Error: $error'))),
    );
  }
}
