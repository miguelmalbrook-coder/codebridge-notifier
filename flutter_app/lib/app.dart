import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/app_config_service.dart';
import 'supabase/client.dart';

class NotifierApp extends StatelessWidget {
  const NotifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codebridge Notifier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A73E8),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A73E8),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: SubscriptionGate(
        child: _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;
    if (session != null && session.accessToken.isNotEmpty) {
      return const HomeScreen();
    }
    return const LoginScreen();
  }
}
