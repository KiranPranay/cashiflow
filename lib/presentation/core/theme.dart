import 'package:flutter/material.dart';

class AppTheme {
  // Brand Default Colors array
  static const Color defaultPrimary = Color(0xFF00E676);
  static const Color darkBackground = Color(0xFF141A1F); 
  static const Color surfaceColor = Color(0xFFFFFFFF);

  static ThemeData buildAdaptiveTheme(ColorScheme? dynamicLight, ColorScheme? dynamicDark, Brightness brightness) {
    // Determine base scheme from dynamic colors or default
    ColorScheme scheme = brightness == Brightness.dark
        ? (dynamicDark ?? ColorScheme.fromSeed(seedColor: defaultPrimary, brightness: Brightness.dark))
        : (dynamicLight ?? ColorScheme.fromSeed(seedColor: defaultPrimary, brightness: Brightness.light));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF6F8FA) : scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: brightness == Brightness.light ? Colors.white : scheme.surfaceContainerHighest,
        elevation: 0, 
        shadowColor: scheme.shadow.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFFFFB74D), // Match the prominent yellow FAB from the mockup
        foregroundColor: Colors.black87,
        elevation: 4,
        highlightElevation: 8,
        shape: const CircleBorder(), // Perfect circle for the bottom notch
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: brightness == Brightness.light ? Colors.white : scheme.surfaceContainer,
        elevation: 16,
        shadowColor: scheme.shadow.withValues(alpha: 0.1),
        shape: const CircularNotchedRectangle(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
