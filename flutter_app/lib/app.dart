import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/camera_list_screen.dart';
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
      home: _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;
    if (session != null && session.accessToken.isNotEmpty) {
      return const CameraListScreen();
    }
    return const LoginScreen();
  }
}
