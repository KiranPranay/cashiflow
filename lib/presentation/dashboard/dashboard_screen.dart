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
import 'package:cashi_flow/presentation/shared/transaction_editor_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    ref.watch(notificationServiceProvider);

    final accountsAsync = ref.watch(accountsStreamProvider);
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final settingsAsync = ref.watch(userSettingsStreamProvider);

    return Scaffold(
      extendBody: true, // required for notched FAB transparent overlay
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              pinned: true,
              leading: IconButton(
                icon: const Icon(Icons.grid_view_rounded),
                onPressed: () {},
              ),
              title: const Text('Dashboard', 
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
            
            // Hero Dashboard Stack
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: _buildHeaderDash(accountsAsync, transactionsAsync, settingsAsync),
              ),
            ),
            
            // Inbox Alerts
            SliverToBoxAdapter(
              child: _buildInboxAlert(transactionsAsync),
            ),

            // Accounts Overview (Optional Scroll)
            SliverToBoxAdapter(
              child: _buildAccountsSection(accountsAsync),
            ),

            // Recent Activity Section
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(left: 24.0, right: 24, top: 32, bottom: 16),
                child: Text('Recent Activity', 
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              ),
            ),
            _buildRecentTransactions(transactionsAsync),
            const SliverToBoxAdapter(child: SizedBox(height: 120)), // Padding for bottom nav
          ],
        ),
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
        double currentMonthIncome = 0;

        transactionsAsync.whenData((txs) {
          final now = DateTime.now();
          for (var t in txs) {
            if (t.status == 'success' && t.timestamp.month == now.month && t.timestamp.year == now.year) {
              if (t.type == 'Expense') currentMonthExpenses += t.amount;
              if (t.type == 'Income') currentMonthIncome += t.amount;
            }
          }
        });

        final isDark = Theme.of(context).brightness == Brightness.dark;

        // Main VISA Card
        return Column(
          children: [
            // Visa Style Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF32363B),
                    Color(0xFF141518),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                    offset: const Offset(0, 8),
                    blurRadius: 24,
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Available balance', 
                        style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
                      Text('CASHI', 
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('₹${netWorth.toStringAsFixed(0)}', 
                    style: const TextStyle(
                      color: Colors.white, 
                      fontSize: 42, fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                    )),
                  const SizedBox(height: 48),
                  const Text('See details', 
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Budget Pill
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget for this month', 
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Cash Available', 
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                    ],
                  ),
                  Text('₹${(netWorth - currentMonthExpenses).clamp(0, double.infinity).toStringAsFixed(0)}', 
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Cash Grid (Income / Expense)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1B5E20).withValues(alpha: 0.2) : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(height: 32),
                        Text('₹${currentMonthIncome.toStringAsFixed(2)}', 
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Income', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF4A148C).withValues(alpha: 0.2) : const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF9C27B0),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(height: 32),
                        Text('₹${currentMonthExpenses.toStringAsFixed(2)}', 
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Expense', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            )
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
            const Padding(
              padding: EdgeInsets.only(left: 24.0, right: 24, top: 24, bottom: 12),
              child: Text('Accounts & Cards', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ),
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: accounts.length + 1,
                itemBuilder: (context, index) {
                  if (index == accounts.length) return _buildAddAccountCard();
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
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(acc.type == 'Credit' ? Icons.credit_card : Icons.account_balance_wallet, 
            color: Theme.of(context).colorScheme.primary, size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(acc.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '₹${acc.balance.abs().toStringAsFixed(0)}', 
                style: TextStyle(
                  fontWeight: FontWeight.w800, 
                  fontSize: 18,
                  color: acc.balance < 0 ? Theme.of(context).colorScheme.error : null,
                )
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAddAccountCard() {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, style: BorderStyle.solid),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {},
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 32),
              SizedBox(height: 8),
              Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
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
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_unread, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '$pendingCount review(s) pending',
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontWeight: FontWeight.bold, fontSize: 16),
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
              return Dismissible(
                key: Key(tx.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
                ),
                onDismissed: (_) async {
                  final repo = ref.read(transactionRepositoryProvider);
                  final accRepo = ref.read(accountRepositoryProvider);
                  
                  // Delete transaction
                  await repo.deleteTransaction(tx.id);
                  
                  // Reverse impact on account
                  if (tx.accountId.isNotEmpty) {
                    final account = await accRepo.getAccountById(tx.accountId);
                    if (account != null) {
                      final newBal = tx.type == 'Expense'
                        ? account.balance + tx.amount
                        : account.balance - tx.amount;
                      await accRepo.updateAccount(account.copyWith(balance: newBal));
                    }
                  }
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transaction deleted')),
                    );
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ]
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    onTap: () => showDialog(
                      context: context, 
                      builder: (ctx) => TransactionEditorDialog(tx: tx)
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tx.type == 'Expense' 
                          ? Theme.of(context).colorScheme.errorContainer 
                          : Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        tx.type == 'Expense' ? Icons.call_made_rounded : Icons.call_received_rounded,
                        color: tx.type == 'Expense' 
                          ? Theme.of(context).colorScheme.onErrorContainer 
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    title: Text(tx.title.isNotEmpty ? tx.title : 'Payment', 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(
                      '${tx.timestamp.day}/${tx.timestamp.month} • ${tx.type}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    trailing: Text(
                      '₹${tx.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: tx.type == 'Expense' ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.primary,
                      ),
                    ),
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
