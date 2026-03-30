import 'package:cashi_flow/presentation/analytics/analytics_screen.dart';
import 'package:cashi_flow/presentation/dashboard/dashboard_screen.dart';
import 'package:cashi_flow/presentation/pay_hub/pay_hub_screen.dart';
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
        path: '/scan',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const PayHubScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: SharedAxisTransitionType.scaled,
              child: child,
            );
          },
        ),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index == 0) context.go('/');
          if (index == 1) context.go('/analytics');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}
