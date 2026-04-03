import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';
import 'package:cashi_flow/presentation/shared/searchable_picker.dart';
import 'package:cashi_flow/presentation/shared/creation_dialogs.dart';

class TransactionEditorDialog extends ConsumerStatefulWidget {
  final TransactionModel tx;
  
  const TransactionEditorDialog({super.key, required this.tx});

  @override
  ConsumerState<TransactionEditorDialog> createState() => _TransactionEditorDialogState();
}

class _TransactionEditorDialogState extends ConsumerState<TransactionEditorDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _refCtrl;
  String? _accountId;
  String? _categoryId;
  String? _destinationAccountId;
  late DateTime _selectedTimestamp;
  String _type = 'Expense';

  bool get _isManual => widget.tx.rawNotificationText == null || widget.tx.rawNotificationText!.isEmpty;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.tx.title);
    _amountCtrl = TextEditingController(text: widget.tx.amount.toStringAsFixed(2));
    _refCtrl = TextEditingController(text: widget.tx.referenceNumber ?? '');
    _selectedTimestamp = widget.tx.timestamp;
    _type = widget.tx.type;
    
    if (widget.tx.accountId.isNotEmpty) {
      _accountId = widget.tx.accountId;
    }
    
    if (widget.tx.categoryId != null && widget.tx.categoryId!.isNotEmpty) {
      _categoryId = widget.tx.categoryId;
    }
    
    if (widget.tx.destinationAccountId != null && widget.tx.destinationAccountId!.isNotEmpty) {
      _destinationAccountId = widget.tx.destinationAccountId;
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
    if (_type == 'Transfer' && (_accountId == null || _destinationAccountId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select From and To Accounts')));
      return;
    }
    if (_type != 'Transfer' && (_accountId == null || _categoryId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select Account and Category')));
      return;
    }

    final repo = ref.read(transactionRepositoryProvider);
    final accRepo = ref.read(accountRepositoryProvider);

    double newAmount = widget.tx.amount;
    if (_isManual) {
      newAmount = double.tryParse(_amountCtrl.text) ?? widget.tx.amount;
    }

    // 1. Rollback old balance if editing already successful one
    if (widget.tx.status == 'success' && widget.tx.accountId.isNotEmpty) {
      final oldAccount = await accRepo.getAccountById(widget.tx.accountId);
      if (oldAccount != null) {
        final reversedBal = widget.tx.type == 'Expense' 
            ? oldAccount.balance + widget.tx.amount
            : (widget.tx.type == 'Income' 
                ? oldAccount.balance - widget.tx.amount
                : oldAccount.balance + widget.tx.amount); // If transfer, source was deducted
        await accRepo.updateAccount(oldAccount.copyWith(balance: reversedBal));
      }
      
      if (widget.tx.type == 'Transfer' && widget.tx.destinationAccountId != null) {
          final oldDest = await accRepo.getAccountById(widget.tx.destinationAccountId!);
          if (oldDest != null) {
             final reversedDestBal = oldDest.balance - widget.tx.amount; // Transfer gave credit
             await accRepo.updateAccount(oldDest.copyWith(balance: reversedDestBal));
          }
      }
    }

    // 2. Adjust New Account Balance with new amount
    final account = await accRepo.getAccountById(_accountId!);
    if (account != null) {
      final newBal = _type == 'Expense' 
        ? account.balance - newAmount 
        : (_type == 'Income' 
           ? account.balance + newAmount
           : account.balance - newAmount); // For transfer, source is deducted
      await accRepo.updateAccount(account.copyWith(balance: newBal));
    }
    
    if (_type == 'Transfer' && _destinationAccountId != null) {
      final destAccount = await accRepo.getAccountById(_destinationAccountId!);
      if (destAccount != null) {
         final newDestBal = destAccount.balance + newAmount;
         await accRepo.updateAccount(destAccount.copyWith(balance: newDestBal));
      }
    }
    
    // 3. Update Transaction Record
    final updatedTx = widget.tx.copyWith(
      title: _titleCtrl.text,
      amount: newAmount,
      accountId: _accountId,
      categoryId: _type != 'Transfer' ? _categoryId : null,
      destinationAccountId: _type == 'Transfer' ? _destinationAccountId : null,
      referenceNumber: _refCtrl.text.isEmpty ? null : _refCtrl.text,
      type: _type,
      timestamp: _selectedTimestamp,
      status: 'success',
    );
    await repo.updateTransaction(updatedTx);

    if (mounted) context.pop();
  }

  void _discard() async {
    final repo = ref.read(transactionRepositoryProvider);
    final accRepo = ref.read(accountRepositoryProvider);

    if (widget.tx.status == 'success' && widget.tx.accountId.isNotEmpty) {
      final account = await accRepo.getAccountById(widget.tx.accountId);
      if (account != null) {
        final reversedBal = widget.tx.type == 'Expense'
            ? account.balance + widget.tx.amount
            : (widget.tx.type == 'Income' 
                ? account.balance - widget.tx.amount
                : account.balance + widget.tx.amount);
        await accRepo.updateAccount(account.copyWith(balance: reversedBal));
      }
      if (widget.tx.type == 'Transfer' && widget.tx.destinationAccountId != null) {
          final oldDest = await accRepo.getAccountById(widget.tx.destinationAccountId!);
          if (oldDest != null) {
             final reversedDestBal = oldDest.balance - widget.tx.amount;
             await accRepo.updateAccount(oldDest.copyWith(balance: reversedDestBal));
          }
      }
    }

    await repo.deleteTransaction(widget.tx.id);
    
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction removed.')));
       context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    
    final List<AccountModel> accounts = accountsAsync.hasValue ? accountsAsync.value! : [];
    final List<CategoryModel> categories = categoriesAsync.hasValue ? categoriesAsync.value! : [];

    if (accounts.isNotEmpty && _accountId != null && !accounts.any((a) => a.id == _accountId)) _accountId = null;
    if (categories.isNotEmpty && _categoryId != null && !categories.any((c) => c.id == _categoryId)) _categoryId = null;
    if (accounts.isNotEmpty && _destinationAccountId != null && !accounts.any((a) => a.id == _destinationAccountId)) _destinationAccountId = null;

    final String accountLabel = _type == 'Income' 
        ? 'Credited To' 
        : (_type == 'Expense' ? 'Debit From' : 'Transfer From');

    return AlertDialog(
      title: Text(widget.tx.status == 'needs_review' ? 'Review Payment' : 'Edit Transaction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Expense', label: Text('Exp'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: 'Transfer', label: Text('Txr'), icon: Icon(Icons.swap_horiz)),
                ButtonSegment(value: 'Income', label: Text('Inc'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_type},
              onSelectionChanged: (set) => setState(() => _type = set.first),
            ),
            const SizedBox(height: 16),
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
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(labelText: 'Reference Code (Optional)', prefixIcon: Icon(Icons.numbers)),
            ),
            const SizedBox(height: 16),
            accountsAsync.when(
              data: (accounts) {
                final selectedAccount = accounts.where((a) => a.id == _accountId).firstOrNull;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance),
                  title: Text(accountLabel),
                  subtitle: Text(selectedAccount?.name ?? 'Select Account'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selected = await SearchablePicker.show<AccountModel>(
                      context: context,
                      title: 'Select Account',
                      items: accounts,
                      itemLabel: (a) => a.name,
                      itemSubtitle: (a) => a.type,
                      addNewLabel: 'Add New Account',
                      onAddNew: () => showAddAccountDialog(context, ref),
                    );
                    if (selected != null) {
                      setState(() => _accountId = selected.id);
                    }
                  },
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => const Text('Error loading accounts'),
            ),
            const SizedBox(height: 16),
            
            if (_type != 'Transfer')
              categoriesAsync.when(
                data: (cats) {
                  final filtered = cats.where((c) => c.type == _type).toList();
                  final selectedCat = filtered.where((c) => c.id == _categoryId).firstOrNull;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.category),
                    title: const Text('Category'),
                    subtitle: Text(selectedCat?.name ?? 'Select Category'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final selected = await SearchablePicker.show<CategoryModel>(
                        context: context,
                        title: 'Select Category',
                        items: filtered,
                        itemLabel: (c) => c.name,
                        addNewLabel: 'Add New Category',
                        onAddNew: () => showAddCategoryDialog(context, ref, defaultType: _type),
                      );
                      if (selected != null) {
                        setState(() => _categoryId = selected.id);
                      }
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, s) => const Text('Error loading categories'),
              ),
              
            if (_type == 'Transfer')
              accountsAsync.when(
                data: (accounts) {
                  final selectedDest = accounts.where((a) => a.id == _destinationAccountId).firstOrNull;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_balance),
                    title: const Text('Transfer To (Account)'),
                    subtitle: Text(selectedDest?.name ?? 'Select Destination Account'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final selected = await SearchablePicker.show<AccountModel>(
                        context: context,
                        title: 'Select Destination Account',
                        items: accounts,
                        itemLabel: (a) => a.name,
                        itemSubtitle: (a) => a.type,
                        addNewLabel: 'Add New Account',
                        onAddNew: () => showAddAccountDialog(context, ref),
                      );
                      if (selected != null) {
                        setState(() => _destinationAccountId = selected.id);
                      }
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, s) => const Text('Error loading accounts'),
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
