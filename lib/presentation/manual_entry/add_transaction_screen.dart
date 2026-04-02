import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/providers/transaction_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amountCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _type = 'Expense';
  String? _accountId;
  String? _categoryId;
  late DateTime _selectedDate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() {
        _selectedDate = DateTime(
          date.year, date.month, date.day,
          _selectedDate.hour, _selectedDate.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (time != null) {
      setState(() {
        _selectedDate = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day,
          time.hour, time.minute,
        );
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save({bool isPending = false}) async {
    if (_amountCtrl.text.isEmpty || _titleCtrl.text.isEmpty || _accountId == null || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final double amt = double.parse(_amountCtrl.text);
      final tx = TransactionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        amount: amt,
        timestamp: _selectedDate,
        title: _titleCtrl.text,
        type: _type,
        accountId: _accountId!,
        categoryId: _categoryId!,
        description: _descCtrl.text,
        status: isPending ? 'pending' : 'success', 
      );

      final repo = ref.read(transactionRepositoryProvider);
      await repo.addTransaction(tx);

      // Only adjust Account balance natively if NOT pending
      if (!isPending) {
        final accountRepo = ref.read(accountRepositoryProvider);
        final account = await accountRepo.getAccountById(_accountId!);
        if (account != null) {
          final double newBal = _type == 'Expense' ? account.balance - amt : account.balance + amt;
          await accountRepo.updateAccount(account.copyWith(balance: newBal));
        }
      }

      HapticFeedback.heavyImpact();
      
      if (isPending) {
        // Universal UPI intent naturally invokes the Android app chooser
        final Uri upiUri = Uri.parse("upi://pay?pa=&pn=&am=$amt");
        if (await canLaunchUrl(upiUri)) {
          await launchUrl(upiUri);
        } else {
          // Fallback if no UPI app installed or intent chooser fails
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No UPI apps found to complete the transaction.')));
        }
      }

      if (mounted) context.pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: _isLoading 
      ? const Center(child: CircularProgressIndicator())
      : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Expense', label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: 'Income', label: Text('Income'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_type},
              onSelectionChanged: (set) => setState(() => _type = set.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(TimeOfDay.fromDateTime(_selectedDate).format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title / Payee', prefixIcon: Icon(Icons.title)),
            ),
            const SizedBox(height: 16),
            
            // Account Selector
            accountsAsync.when(
              data: (accounts) => DropdownButtonFormField<String>(
                value: _accountId,
                items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                onChanged: (v) => setState(() => _accountId = v),
                decoration: const InputDecoration(labelText: 'Account', prefixIcon: Icon(Icons.account_balance)),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => const Text('Error loading accounts'),
            ),
            
            const SizedBox(height: 16),
            // Category Selector
            categoriesAsync.when(
              data: (cats) {
                final filtered = cats.where((c) => c.type == _type).toList();
                return DropdownButtonFormField<String>(
                  value: _categoryId,
                  items: filtered.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                  decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category)),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, s) => const Text('Error loading categories'),
            ),
            
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Notes (Optional)', prefixIcon: Icon(Icons.note)),
              maxLines: 2,
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _save(isPending: true),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Save & Open App\n(Auto Verify)'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _save(isPending: false),
                    icon: const Icon(Icons.save),
                    label: const Text('Save Directly'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
