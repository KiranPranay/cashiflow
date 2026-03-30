import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';
import 'package:cashi_flow/domain/providers/user_settings_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // State
  final Map<String, double> _incomes = {'Primary Salary': 0.0};
  final List<AccountModel> _accounts = [];
  bool _isLoading = false;

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() => _isLoading = true);

    final String baseAccountId = _accounts.isNotEmpty ? _accounts.first.id : 'default';

    // 1. Save Settings
    final settingsRepo = ref.read(userSettingsRepositoryProvider);
    await settingsRepo.saveSettings(UserSettingsModel(
      expectedIncomes: _incomes,
      baseBankAccountId: baseAccountId,
      onboardingCompleted: true,
    ));

    // 2. Save Accounts
    final accountRepo = ref.read(accountRepositoryProvider);
    for (final acc in _accounts) {
      await accountRepo.addAccount(acc);
    }

    // 3. Generate Default Categories
    final catRepo = ref.read(categoryRepositoryProvider);
    final defaults = [
      CategoryModel(id: 'cat_1', name: 'Food & Dining', type: 'Expense', iconName: 'restaurant', colorHex: 0xFFFF5252),
      CategoryModel(id: 'cat_2', name: 'Shopping', type: 'Expense', iconName: 'shopping_bag', colorHex: 0xFF448AFF),
      CategoryModel(id: 'cat_3', name: 'Transport', type: 'Expense', iconName: 'directions_car', colorHex: 0xFFFFB300),
      CategoryModel(id: 'cat_4', name: 'Bills & Utilities', type: 'Expense', iconName: 'bolt', colorHex: 0xFF00B0FF),
      CategoryModel(id: 'cat_5', name: 'Salary', type: 'Income', iconName: 'account_balance_wallet', colorHex: 0xFF00E676),
    ];
    for (final cat in defaults) {
      await catRepo.addCategory(cat);
    }

    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _IncomeStep(
                    incomes: _incomes,
                    onUpdate: (map) => setState((){}),
                  ),
                  _BankStep(
                    accounts: _accounts,
                    onUpdate: () => setState((){}),
                  ),
                  _FinishStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox.shrink(),
                  
                  FilledButton(
                    onPressed: _nextPage,
                    child: Text(_currentPage == 2 ? 'Let\'s Go' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Step 1: Incomes
// ----------------------------------------------------------------------
class _IncomeStep extends StatefulWidget {
  final Map<String, double> incomes;
  final Function(Map<String, double>) onUpdate;

  const _IncomeStep({required this.incomes, required this.onUpdate});

  @override
  State<_IncomeStep> createState() => _IncomeStepState();
}

class _IncomeStepState extends State<_IncomeStep> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _amtCtrl = TextEditingController();

  void _addIncome() {
    if (_nameCtrl.text.isNotEmpty && _amtCtrl.text.isNotEmpty) {
      final amt = double.tryParse(_amtCtrl.text) ?? 0.0;
      widget.incomes[_nameCtrl.text] = amt;
      _nameCtrl.clear();
      _amtCtrl.clear();
      widget.onUpdate(widget.incomes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Expected Income', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Declare your expected monthly income sources (Salary, Freelance, etc.) to set baseline savings goals.'),
          const SizedBox(height: 24),
          ...widget.incomes.entries.map((e) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.monetization_on),
            title: Text(e.key),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('₹${e.value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    widget.incomes.remove(e.key);
                    widget.onUpdate(widget.incomes);
                  },
                )
              ],
            ),
          )),
          const Divider(),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Source Name'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ),
              IconButton(onPressed: _addIncome, icon: const Icon(Icons.add_circle, size: 32, color: Colors.green)),
            ],
          )
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Step 2: Banks and Cards
// ----------------------------------------------------------------------
class _BankStep extends StatefulWidget {
  final List<AccountModel> accounts;
  final VoidCallback onUpdate;

  const _BankStep({required this.accounts, required this.onUpdate});

  @override
  State<_BankStep> createState() => _BankStepState();
}

class _BankStepState extends State<_BankStep> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _balCtrl = TextEditingController();
  final TextEditingController _limitCtrl = TextEditingController();
  String _type = 'Bank'; // Bank or Credit

  void _addAccount() {
    if (_nameCtrl.text.isNotEmpty && _balCtrl.text.isNotEmpty) {
      final bal = double.tryParse(_balCtrl.text) ?? 0.0;
      final limit = double.tryParse(_limitCtrl.text) ?? 0.0;
      
      widget.accounts.add(AccountModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameCtrl.text,
        type: _type,
        balance: _type == 'Credit' ? -bal.abs() : bal, // Credit used is negative balance
        creditLimit: limit,
        iconName: _type == 'Credit' ? 'credit_card' : 'account_balance',
      ));
      
      _nameCtrl.clear();
      _balCtrl.clear();
      _limitCtrl.clear();
      widget.onUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accounts', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Add your Bank Accounts and Credit Cards with their current balances.'),
            const SizedBox(height: 24),
            ...widget.accounts.map((e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(e.type == 'Credit' ? Icons.credit_card : Icons.account_balance),
              title: Text(e.name),
              subtitle: Text(e.type),
              trailing: Text('₹${e.balance.toStringAsFixed(0)}', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16,
                color: e.balance < 0 ? Colors.redAccent : Colors.greenAccent
              )),
            )),
            const Divider(),
            DropdownButtonFormField<String>(
              value: _type,
              items: ['Bank', 'Credit', 'Wallet', 'Cash'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _type = v!),
              decoration: const InputDecoration(labelText: 'Account Type'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Account Name')),
            const SizedBox(height: 12),
            TextField(
              controller: _balCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _type == 'Credit' ? 'Current Outstanding Bill' : 'Current Balance'),
            ),
            if (_type == 'Credit') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total Credit Limit'),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _addAccount, 
                icon: const Icon(Icons.add), 
                label: const Text('Add Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Step 3: Finish
// ----------------------------------------------------------------------
class _FinishStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 100, color: Colors.greenAccent),
          const SizedBox(height: 24),
          Text('All Set!', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            'We will track your payments via notifications and flag them for your review. No more manual data entry or double scanning!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
