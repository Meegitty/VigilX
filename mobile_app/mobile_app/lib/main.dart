import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const CrashSOSApp());
}

class CrashSOSApp extends StatelessWidget {
  const CrashSOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF6F1E7); // beige/cream
    const blue = Color(0xFF1E5AA8);

    final theme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        brightness: Brightness.light,
        background: cream,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Crash SOS',
      theme: theme,
      home: const HomeScreen(),
    );
  }
}