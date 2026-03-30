import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:cashi_flow/domain/models/transaction_model.dart';
import 'package:cashi_flow/domain/models/account_model.dart';
import 'package:cashi_flow/domain/models/category_model.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:cashi_flow/presentation/core/router.dart';
import 'package:cashi_flow/presentation/core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await Hive.initFlutter();
  
  // Safely delete legacy data structure (approved wipe)
  try {
    await Hive.deleteBoxFromDisk('transactions');
  } catch (_) {}
  
  // Register Adapters
  Hive.registerAdapter(TransactionModelAdapter());
  Hive.registerAdapter(AccountModelAdapter());
  Hive.registerAdapter(CategoryModelAdapter());
  Hive.registerAdapter(UserSettingsModelAdapter());
  
  // Bulletproof Hive bootloader
  final boxes = [
    ('transactions_v2', () => Hive.openBox<TransactionModel>('transactions_v2')),
    ('accounts', () => Hive.openBox<AccountModel>('accounts')),
    ('categories', () => Hive.openBox<CategoryModel>('categories')),
    ('user_settings', () => Hive.openBox<UserSettingsModel>('user_settings')),
  ];

  for (final box in boxes) {
    try {
      await box.$2();
    } catch (e) {
      print('Hive Error opening ${box.$1}: $e. Forcing nuke.');
      await Hive.deleteBoxFromDisk(box.$1);
      await box.$2(); // Try again with fresh slate
    }
  }
  
  runApp(
    const ProviderScope(
      child: CashiFlowApp(),
    ),
  );
}

class CashiFlowApp extends ConsumerStatefulWidget {
  const CashiFlowApp({super.key});

  @override
  ConsumerState<CashiFlowApp> createState() => _CashiFlowAppState();
}

class _CashiFlowAppState extends ConsumerState<CashiFlowApp> {
  final QuickActions quickActions = const QuickActions();

  @override
  void initState() {
    super.initState();
    quickActions.initialize((String shortcutType) {
      if (shortcutType == 'action_scan') {
        ref.read(routerProvider).push('/scan');
      }
    });

    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
        type: 'action_scan',
        localizedTitle: 'Scan & Pay',
        icon: 'ic_launcher',
      )
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // Feed the dynamic colors into our AppTheme generator
        final isDark = Brightness.dark == MediaQuery.platformBrightnessOf(context);
        final theme = AppTheme.buildAdaptiveTheme(
          lightDynamic, 
          darkDynamic, 
          isDark ? Brightness.dark : Brightness.light
        );
        
        return MaterialApp.router(
          title: 'Cashi Flow',
          theme: theme,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
