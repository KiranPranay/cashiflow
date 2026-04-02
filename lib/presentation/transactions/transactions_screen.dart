import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';
import 'package:cashi_flow/presentation/shared/transaction_editor_dialog.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  String _sortOrder = 'Newest First'; // or 'Oldest First'
  
  bool _showFilters = false;

  void _clearFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedAccountId = null;
      _selectedCategoryId = null;
      _sortOrder = 'Newest First';
    });
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    final accounts = accountsAsync.valueOrNull ?? [];
    final categories = categoriesAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showFilters)
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      TextButton(onPressed: _clearFilters, child: const Text('Clear All')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDateRange,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(_startDate != null && _endDate != null
                        ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                        : 'Select Date Range'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedAccountId,
                          decoration: const InputDecoration(labelText: 'Account / Card', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Accounts')),
                            ...accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          ],
                          onChanged: (val) => setState(() => _selectedAccountId = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedCategoryId,
                          decoration: const InputDecoration(labelText: 'Category', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Categories')),
                            ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                          ],
                          onChanged: (val) => setState(() => _selectedCategoryId = val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _sortOrder,
                    decoration: const InputDecoration(labelText: 'Sort By', contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                    items: ['Newest First', 'Oldest First'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (val) => setState(() => _sortOrder = val!),
                  ),
                ],
              ),
            ),
          Expanded(
            child: transactionsAsync.when(
              data: (txs) {
                // Apply filters
                var filteredTxs = txs.where((t) => t.status == 'success').toList();

                if (_startDate != null && _endDate != null) {
                  // End date should encompass the entire day
                  final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
                  filteredTxs = filteredTxs.where((t) => 
                    t.timestamp.isAfter(_startDate!) && t.timestamp.isBefore(endOfDay) || 
                    t.timestamp.isAtSameMomentAs(_startDate!) || 
                    t.timestamp.isAtSameMomentAs(endOfDay)
                  ).toList();
                }

                if (_selectedAccountId != null) {
                  filteredTxs = filteredTxs.where((t) => 
                     t.accountId == _selectedAccountId || 
                     (t.type == 'Transfer' && t.destinationAccountId == _selectedAccountId)
                  ).toList();
                }

                if (_selectedCategoryId != null) {
                  filteredTxs = filteredTxs.where((t) => t.categoryId == _selectedCategoryId).toList();
                }

                // Apply Sort
                if (_sortOrder == 'Newest First') {
                  filteredTxs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                } else {
                  filteredTxs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                }

                if (filteredTxs.isEmpty) {
                  return const Center(child: Text('No transactions match the criteria.'));
                }

                return ListView.builder(
                  itemCount: filteredTxs.length,
                  itemBuilder: (context, index) {
                    final tx = filteredTxs[index];
                    return ListTile(
                      onTap: () => showDialog(
                        context: context, 
                        builder: (ctx) => TransactionEditorDialog(tx: tx)
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tx.type == 'Transfer'
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : (tx.type == 'Expense' 
                                ? Theme.of(context).colorScheme.errorContainer 
                                : Theme.of(context).colorScheme.primaryContainer),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          tx.type == 'Transfer' ? Icons.swap_horiz : (tx.type == 'Expense' ? Icons.call_made_rounded : Icons.call_received_rounded),
                          color: tx.type == 'Transfer'
                            ? Theme.of(context).colorScheme.onSecondaryContainer
                            : (tx.type == 'Expense' 
                                ? Theme.of(context).colorScheme.onErrorContainer 
                                : Theme.of(context).colorScheme.onPrimaryContainer),
                          size: 20,
                        ),
                      ),
                      title: Text(tx.title.isNotEmpty ? tx.title : 'Payment', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tx.timestamp.day}/${tx.timestamp.month}/${tx.timestamp.year} • ${TimeOfDay.fromDateTime(tx.timestamp).format(context)} • ${tx.type}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                          ),
                          if (tx.referenceNumber != null && tx.referenceNumber!.isNotEmpty)
                            Text(
                              'Ref: ${tx.referenceNumber}',
                              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                            ),
                        ],
                      ),
                      trailing: Text(
                        '₹${tx.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: tx.type == 'Transfer' 
                            ? Theme.of(context).colorScheme.onSurface
                            : (tx.type == 'Expense' ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error loading transactions ($err)')),
            ),
          )
        ],
      ),
    );
  }
}
