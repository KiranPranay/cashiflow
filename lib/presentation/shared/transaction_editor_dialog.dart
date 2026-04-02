import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';

class TransactionEditorDialog extends ConsumerStatefulWidget {
  final TransactionModel tx;
  
  const TransactionEditorDialog({super.key, required this.tx});

  @override
  ConsumerState<TransactionEditorDialog> createState() => _TransactionEditorDialogState();
}

class _TransactionEditorDialogState extends ConsumerState<TransactionEditorDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _amountCtrl;
  String? _accountId;
  String? _categoryId;
  late DateTime _selectedTimestamp;

  bool get _isManual => widget.tx.rawNotificationText == null || widget.tx.rawNotificationText!.isEmpty;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.tx.title);
    _amountCtrl = TextEditingController(text: widget.tx.amount.toStringAsFixed(2));
    _selectedTimestamp = widget.tx.timestamp;
    
    if (widget.tx.accountId.isNotEmpty) {
      _accountId = widget.tx.accountId;
    }
    
    if (widget.tx.categoryId != null && widget.tx.categoryId!.isNotEmpty) {
      _categoryId = widget.tx.categoryId;
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedTimestamp,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() {
        _selectedTimestamp = DateTime(
          date.year, date.month, date.day,
          _selectedTimestamp.hour, _selectedTimestamp.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTimestamp),
    );
    if (time != null) {
      setState(() {
        _selectedTimestamp = DateTime(
          _selectedTimestamp.year, _selectedTimestamp.month, _selectedTimestamp.day,
          time.hour, time.minute,
        );
      });
    }
  }

  void _confirm(List<AccountModel> accounts, List<CategoryModel> categories) async {
    // If _accountId or _categoryId remains null even though user intended to pick one, enforce it!
    if (_accountId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select Account and Category')));
      return;
    }

    // Safety fallback: if somehow the selected ID is not in the fully loaded list 
    final isAccountValid = accounts.any((a) => a.id == _accountId);
    final isCategoryValid = categories.any((c) => c.id == _categoryId);
    
    if (!isAccountValid || !isCategoryValid) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select valid options from the drop down.')));
       return;
    }

    final repo = ref.read(transactionRepositoryProvider);
    final accRepo = ref.read(accountRepositoryProvider);

    double newAmount = widget.tx.amount;
    if (_isManual) {
      newAmount = double.tryParse(_amountCtrl.text) ?? widget.tx.amount;
    }

    // 1. If modifying an ALREADY SUCCESSFUL transaction, we must rollback the old balance first.
    if (widget.tx.status == 'success' && widget.tx.accountId.isNotEmpty) {
      final oldAccount = await accRepo.getAccountById(widget.tx.accountId);
      if (oldAccount != null) {
        final reversedBal = widget.tx.type == 'Expense'
            ? oldAccount.balance + widget.tx.amount
            : oldAccount.balance - widget.tx.amount;
        await accRepo.updateAccount(oldAccount.copyWith(balance: reversedBal));
      }
    }

    // 2. Adjust New Account Balance with potentially new amount
    final account = await accRepo.getAccountById(_accountId!);
    if (account != null) {
      final newBal = widget.tx.type == 'Expense' 
        ? account.balance - newAmount 
        : account.balance + newAmount;
      await accRepo.updateAccount(account.copyWith(balance: newBal));
    }
    
    // 3. Update Transaction Record
    final updatedTx = widget.tx.copyWith(
      title: _titleCtrl.text,
      amount: newAmount,
      accountId: _accountId,
      categoryId: _categoryId,
      timestamp: _selectedTimestamp,
      status: 'success',
    );
    await repo.updateTransaction(updatedTx);

    if (mounted) context.pop();
  }

  void _discard() async {
    final repo = ref.read(transactionRepositoryProvider);
    final accRepo = ref.read(accountRepositoryProvider);

    // If it's merely a "needs_review" item, deletion is safe.
    // However, if the user explicitly presses 'Discard' or 'Delete' on an already-confirmed item 
    // from this dialog, we should reverse balance just like swipe-to-delete.
    if (widget.tx.status == 'success' && widget.tx.accountId.isNotEmpty) {
      final account = await accRepo.getAccountById(widget.tx.accountId);
      if (account != null) {
        final reversedBal = widget.tx.type == 'Expense'
            ? account.balance + widget.tx.amount
            : account.balance - widget.tx.amount;
        await accRepo.updateAccount(account.copyWith(balance: reversedBal));
      }
    }

    await repo.deleteTransaction(widget.tx.id);
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction removed for good.')));
       context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    
    final List<AccountModel> accounts = accountsAsync.hasValue ? accountsAsync.value! : [];
    final List<CategoryModel> categories = categoriesAsync.hasValue ? categoriesAsync.value! : [];

    // Ensure _accountId is actually in the items list, otherwise set to null
    // This prevents "DropdownButton: There should be exactly one item with [DropdownButton]'s value" exception
    if (accounts.isNotEmpty && _accountId != null && !accounts.any((a) => a.id == _accountId)) {
      _accountId = null;
    }

    if (categories.isNotEmpty && _categoryId != null && !categories.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }

    final String accountLabel = widget.tx.type == 'Income' 
        ? 'Credited To (Account)' 
        : 'Debit From (Account)';

    return AlertDialog(
      title: Text(widget.tx.status == 'needs_review' ? 'Review Payment' : 'Edit Transaction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isManual)
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(prefixText: '₹ ', border: InputBorder.none),
              )
            else
              Text('₹${widget.tx.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('${_selectedTimestamp.day}/${_selectedTimestamp.month}/${_selectedTimestamp.year}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(TimeOfDay.fromDateTime(_selectedTimestamp).format(context)),
                  ),
                ),
              ],
            ),
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
              decoration: InputDecoration(labelText: accountLabel),
              hint: accountsAsync.isLoading ? const Text('Loading accounts...') : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _categoryId,
              items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _categoryId = v),
              decoration: const InputDecoration(labelText: 'Category'),
              hint: categoriesAsync.isLoading ? const Text('Loading categories...') : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _discard, 
          child: Text(widget.tx.status == 'needs_review' ? 'Discard' : 'Delete', style: const TextStyle(color: Colors.red))
        ),
        FilledButton(
          onPressed: () => _confirm(accounts, categories), 
          child: Text(widget.tx.status == 'needs_review' ? 'Verify & Save' : 'Save Changes')
        ),
      ],
    );
  }
}
