import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/providers/user_settings_providers.dart';
import 'package:cashi_flow/domain/providers/account_providers.dart';
import 'package:cashi_flow/domain/providers/category_providers.dart';
import 'package:cashi_flow/data/services/notification_service.dart';
import 'package:cashi_flow/data/services/backup_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 24),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(userSettingsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration & Settings'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('FINANCIAL STRUCTURE'),
                _buildSettingsGroup([
                  // Income
                  settingsAsync.when(
                    data: (settings) {
                      if (settings == null) return const SizedBox.shrink();
                      final totalIncome = settings.expectedIncomes.values.fold<double>(0.0, (s, amt) => s + amt);
                      return ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        leading: const Icon(Icons.account_balance_wallet_rounded, color: Colors.green),
                        title: const Text('Income Sources', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Expected: ₹${totalIncome.toStringAsFixed(0)} / mo'),
                        children: [
                          ...settings.expectedIncomes.entries.map((e) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                            title: Text(e.key),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('₹${e.value.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteIncome(settings, e.key)),
                              ],
                            ),
                          )),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
                            title: const Text('Add Income Source', style: TextStyle(color: Colors.green)),
                            onTap: () => _showAddIncomeDialog(settings),
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),

                  // Accounts
                  accountsAsync.when(
                    data: (accounts) => ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: const Icon(Icons.account_balance_rounded, color: Colors.blue),
                      title: const Text('Accounts & Cards', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${accounts.length} linked assets'),
                      children: [
                        ...accounts.map((acc) => ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                          title: Text(acc.name),
                          subtitle: Text(acc.type),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('₹${acc.balance.abs().toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteAccount(acc.id)),
                            ],
                          ),
                        )),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                          leading: const Icon(Icons.add_circle_outline, color: Colors.blue),
                          title: const Text('Link New Account', style: TextStyle(color: Colors.blue)),
                          onTap: () => _showAddAccountDialog(),
                        ),
                      ],
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),

                  // Categories
                  categoriesAsync.when(
                    data: (cats) => ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: const Icon(Icons.category_rounded, color: Colors.orange),
                      title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${cats.length} active tags'),
                      children: [
                        ...cats.map((cat) => ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                          title: Text(cat.name),
                          subtitle: Text(cat.type),
                          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteCategory(cat.id)),
                        )),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                          leading: const Icon(Icons.add_circle_outline, color: Colors.orange),
                          title: const Text('Create Category', style: TextStyle(color: Colors.orange)),
                          onTap: () => _showAddCategoryDialog(),
                        ),
                      ],
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ]),

                _buildSectionHeader('SYSTEM INTEGRATIONS'),
                _buildSettingsGroup([
                  // AI Parser
                  settingsAsync.when(
                    data: (settings) => ListTile(
                      leading: const Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                      title: const Text('Gemini Engine API', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(settings?.geminiApiKey != null ? 'Linked' : 'Not configured'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showEditGeminiKeyDialog(settings),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  
                  // Permissions
                  FutureBuilder<bool>(
                    future: NotificationService.isPermissionGranted(),
                    builder: (context, snapshot) {
                      final isGranted = snapshot.data ?? false;
                      return ListTile(
                        leading: const Icon(Icons.shield_rounded, color: Colors.blueGrey),
                        title: const Text('Offline Text Sync', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(isGranted ? 'Active' : 'Missing access'),
                        trailing: Icon(isGranted ? Icons.check_circle : Icons.warning_amber_rounded, color: isGranted ? Colors.green : Colors.red),
                        onTap: () async {
                          await NotificationService.requestPermission();
                          setState(() {});
                        },
                      );
                    },
                  ),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),

                  // Battery
                  ListTile(
                    leading: const Icon(Icons.battery_charging_full_rounded, color: Colors.blueGrey),
                    title: const Text('Unrestricted Battery', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Required for background processing'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please allow background usage in Android App Info settings.')),
                      );
                    },
                  ),
                ]),

                _buildSectionHeader('MAINTENANCE'),
                _buildSettingsGroup([
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                    title: const Text('Wipe All Data', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Erases ledger completely'),
                    onTap: () => _confirmWipe(context, ref),
                  ),
                ]),

                _buildSectionHeader('DATA MANAGEMENT'),
                _buildSettingsGroup([
                  ListTile(
                    leading: const Icon(Icons.upload_file, color: Colors.blue),
                    title: const Text('Export Backup', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Save your data locally'),
                    onTap: () => _exportData(context, ref),
                  ),
                  Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ListTile(
                    leading: const Icon(Icons.download_rounded, color: Colors.green),
                    title: const Text('Restore Data', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Import from a local backup'),
                    onTap: () => _confirmImport(context, ref),
                  ),
                ]),
                
                
                const SizedBox(height: 120),
              ],
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

  void _exportData(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing backup...')));
    final backupSvc = ref.read(backupServiceProvider);
    final success = await backupSvc.exportBackup();
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup exported successfully!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export cancelled or failed.')));
      }
    }
  }

  void _confirmImport(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Warning', style: TextStyle(color: Colors.orange)),
        content: const Text('Restoring a backup will irrevocably OVERWRITE all current data. Do you wish to proceed?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Proceed & Overwrite')
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Awaiting file selection...')));
      final backupSvc = ref.read(backupServiceProvider);
      final success = await backupSvc.importBackup();
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data restored successfully! Restarting...')));
          context.go('/onboarding');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import cancelled or data invalid.')));
        }
      }
    }
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
      await Hive.box<TransactionModel>('transactions_v2').clear();
      await Hive.box<AccountModel>('accounts').clear();
      await Hive.box<CategoryModel>('categories').clear();
      await Hive.box<UserSettingsModel>('user_settings').clear();
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
