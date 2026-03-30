import 'package:flutter/material.dart';

class AppTheme {
  // Brand Default Colors array
  static const Color defaultPrimary = Color(0xFF00E676);
  static const Color darkBackground = Color(0xFF141A1F); // slightly blueish dark
  static const Color surfaceColor = Color(0xFF222831);
  
  // Legacy statics to prevent compilation errors before full migration:
  static const Color deepCharcoal = Color(0xFF1E2022);
  static const Color electricMint = Color(0xFF00E676);
  static const Color onSurfaceColor = Color(0xFFF5F5F5);
  static const Color errorColor = Color(0xFFFF5252);

  static ThemeData buildAdaptiveTheme(ColorScheme? dynamicDark) {
    final ColorScheme scheme = dynamicDark ?? 
        ColorScheme.fromSeed(
          seedColor: defaultPrimary,
          brightness: Brightness.dark,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 8, // High elevation for key stats
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: electricMint,
        foregroundColor: deepCharcoal,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
