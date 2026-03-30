import 'package:cashi_flow/presentation/analytics/analytics_screen.dart';
import 'package:cashi_flow/presentation/dashboard/dashboard_screen.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animations/animations.dart';
import 'package:cashi_flow/presentation/onboarding/onboarding_screen.dart';
import 'package:cashi_flow/presentation/inbox/inbox_screen.dart';
import 'package:cashi_flow/presentation/manual_entry/add_transaction_screen.dart';
import 'package:cashi_flow/presentation/settings/settings_screen.dart';
import 'package:hive/hive.dart';
import 'package:cashi_flow/domain/models/user_settings_model.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final box = Hive.box<UserSettingsModel>('user_settings');
      final settings = box.get('settings');
      final isCompleted = settings?.onboardingCompleted ?? false;
      
      final goingToOnboarding = state.matchedLocation == '/onboarding';
      
      if (!isCompleted && !goingToOnboarding) {
        return '/onboarding';
      } else if (isCompleted && goingToOnboarding) {
        return '/';
      }
      return null;
    },
    routes: [
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/analytics',
            builder: (context, state) => const AnalyticsScreen(),
          ),
        ],
      ),

      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/inbox',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const InboxScreen(),
      ),
      GoRoute(
        path: '/add_transaction',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AddTransactionScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});

class AppScaffold extends StatelessWidget {
  final Widget child;
  const AppScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Current route to manage navigation bar state
    final GoRouterState state = GoRouterState.of(context);
    final String location = state.uri.toString();
    
    int currentIndex = location == '/' ? 0 : 1;

    return Scaffold(
      body: child,
      extendBody: true, // required for notched bottom app bar transparency
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add_transaction'),
        child: const Icon(Icons.add, size: 28),
      ),
      bottomNavigationBar: BottomAppBar(
        notchMargin: 8.0,
        height: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavBarIcon(
              icon: Icons.home_rounded,
              isSelected: currentIndex == 0,
              onTap: () => context.go('/'),
            ),
            _NavBarIcon(
              icon: Icons.calendar_today_rounded,
              isSelected: false,
              onTap: () {}, // Placeholder for future calendar route
            ),
            const SizedBox(width: 48), // Space for the notched FAB
            _NavBarIcon(
              icon: Icons.account_balance_wallet_rounded,
              isSelected: currentIndex == 1,
              onTap: () => context.go('/analytics'),
            ),
            _NavBarIcon(
              icon: Icons.person_outline_rounded,
              isSelected: false,
              onTap: () => context.push('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBarIcon extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarIcon({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
        
    return IconButton(
      icon: Icon(icon, size: 28),
      color: color,
      onPressed: onTap,
    );
  }
}
