import 'package:flutter/material.dart';
import 'app.dart';
import 'services/ntfy_service.dart';
import 'supabase/client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase with env vars passed at build time
  await initSupabase();

  // Start ntfy push notifications
  await NtfyService().start();

  runApp(const NotifierApp());
}
