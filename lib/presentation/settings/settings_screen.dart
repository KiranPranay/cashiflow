import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
import 'package:cashi_flow/domain/providers/user_settings_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';
import 'package:cashi_flow/data/services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(userSettingsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration & Settings')),
      body: CustomScrollView(
        slivers: [
          // Income Sources
          SliverToBoxAdapter(
            child: settingsAsync.when(
              data: (settings) {
                if (settings == null) return const SizedBox.shrink();
                final incomes = settings.expectedIncomes;
                final totalIncome = incomes.values.fold<double>(0.0, (s, amt) => s + amt);

                return ExpansionTile(
                  initiallyExpanded: true,
                  leading: const Icon(Icons.account_balance_wallet, color: Colors.green),
                  title: const Text('Income Sources', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Total Expected: ₹${totalIncome.toStringAsFixed(0)}'),
                  children: [
                    ...incomes.entries.map((e) => ListTile(
                      title: Text(e.key),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('₹${e.value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteIncome(settings, e.key),
                          ),
                        ],
                      ),
                    )),
                    TextButton.icon(
                      onPressed: () => _showAddIncomeDialog(settings),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Income Source'),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: Divider()),

          // Accounts
          SliverToBoxAdapter(
            child: accountsAsync.when(
              data: (accounts) => ExpansionTile(
                leading: const Icon(Icons.account_balance, color: Colors.blue),
                title: const Text('Accounts & Credit Cards', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${accounts.length} linked accounts'),
                children: [
                  ...accounts.map((acc) => ListTile(
                    leading: Icon(acc.type == 'Credit' ? Icons.credit_card : Icons.monetization_on),
                    title: Text(acc.name),
                    subtitle: Text('${acc.type} • ₹${acc.balance.toStringAsFixed(0)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteAccount(acc.id),
                    ),
                  )),
                  TextButton.icon(
                    onPressed: () => _showAddAccountDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Account / Card'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: Divider()),

          // Categories
          SliverToBoxAdapter(
            child: categoriesAsync.when(
              data: (cats) => ExpansionTile(
                leading: const Icon(Icons.category, color: Colors.orange),
                title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${cats.length} active categories'),
                children: [
                  ...cats.map((cat) => ListTile(
                    leading: const Icon(Icons.label),
                    title: Text(cat.name),
                    subtitle: Text(cat.type),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteCategory(cat.id),
                    ),
                  )),
                  TextButton.icon(
                    onPressed: () => _showAddCategoryDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Custom Category'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // App Permissions
          SliverToBoxAdapter(
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.security, color: Colors.blueGrey),
              title: const Text('System Permissions', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Manage background data access'),
              children: [
                FutureBuilder<bool>(
                  future: NotificationService.isPermissionGranted(),
                  builder: (context, snapshot) {
                    final isGranted = snapshot.data ?? false;
                    return ListTile(
                      title: const Text('Notification Listener'),
                      subtitle: Text(
                        isGranted 
                          ? 'Active • Capturing background banking SMS' 
                          : 'Missing • App cannot read SMS offline. Tap to enable.',
                        style: TextStyle(
                          color: isGranted ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: isGranted ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      trailing: Icon(
                        isGranted ? Icons.check_circle : Icons.warning_amber_rounded,
                        color: isGranted ? Colors.green : Colors.red,
                      ),
                      onTap: () async {
                        await NotificationService.requestPermission();
                        // Trigger a rebuild when returning to update status
                        setState(() {});
                      },
                    );
                  },
                ),
                ListTile(
                  title: const Text('Battery Management'),
                  subtitle: const Text('Ensure app is allowed un-restricted background usage to prevent dropping tasks.'),
                  trailing: const Icon(Icons.battery_saver, color: Colors.grey),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Check your Physical Device Settings -> Apps -> Cashi Flow -> Battery -> Set to Unrestricted.')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SliverToBoxAdapter(child: Divider()),

          // Integrations
          SliverToBoxAdapter(
            child: settingsAsync.when(
              data: (settings) => ExpansionTile(
                leading: const Icon(Icons.api, color: Colors.purple),
                title: const Text('Integrations & AI', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Configure Gemini AI parser'),
                children: [
                  ListTile(
                    title: const Text('Gemini API Key'),
                    subtitle: Text(settings?.geminiApiKey != null ? 'Key configured (starts with ${settings!.geminiApiKey!.substring(0, 4)}...)' : 'Not configured'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _showEditGeminiKeyDialog(settings),
                  ),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),

          // Danger Zone
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text('Danger Zone', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                        onPressed: () => _confirmWipe(context, ref),
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Wipe All Data & Restart Setup'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Actions ---

  void _deleteIncome(UserSettingsModel settings, String key) {
    final newIncomes = Map<String, double>.from(settings.expectedIncomes)..remove(key);
    ref.read(userSettingsRepositoryProvider).saveSettings(settings.copyWith(expectedIncomes: newIncomes));
  }

  void _showAddIncomeDialog(UserSettingsModel settings) {
    final nameCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Income Source'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Freelance)')),
          TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount/Month')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final amt = double.tryParse(amtCtrl.text) ?? 0;
          if (nameCtrl.text.isNotEmpty && amt > 0) {
            final newIncomes = Map<String, double>.from(settings.expectedIncomes);
            newIncomes[nameCtrl.text] = amt;
            ref.read(userSettingsRepositoryProvider).saveSettings(settings.copyWith(expectedIncomes: newIncomes));
            Navigator.pop(ctx);
          }
        }, child: const Text('Add')),
      ],
    ));
  }

  void _deleteAccount(String id) {
    ref.read(accountRepositoryProvider).deleteAccount(id);
  }

  void _showAddAccountDialog() {
    final nameCtrl = TextEditingController();
    final balCtrl = TextEditingController();
    String type = 'Bank';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
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
    ));
  }

  void _deleteCategory(String id) {
    ref.read(categoryRepositoryProvider).deleteCategory(id);
  }

  void _showAddCategoryDialog() {
    final nameCtrl = TextEditingController();
    String type = 'Expense';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
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
    ));
  }

  void _confirmWipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Red Alert', style: TextStyle(color: Colors.red)),
        content: const Text('Are you unconditionally sure you want to wipe everything and restart the app?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Wipe Everything')
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Hive.box('transactions_v2').clear();
      await Hive.box('accounts').clear();
      await Hive.box('categories').clear();
      await Hive.box('user_settings').clear();
      if (context.mounted) {
        context.go('/onboarding');
      }
    }
  }

  void _showEditGeminiKeyDialog(UserSettingsModel? settings) {
    if (settings == null) return;
    final keyCtrl = TextEditingController(text: settings.geminiApiKey);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Gemini API Key'),
      content: TextField(
        controller: keyCtrl, 
        decoration: const InputDecoration(labelText: 'AI/Studio API Key'),
        obscureText: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          ref.read(userSettingsRepositoryProvider).saveSettings(
            settings.copyWith(geminiApiKey: keyCtrl.text.isEmpty ? null : keyCtrl.text)
          );
          Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }
}
