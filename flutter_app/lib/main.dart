import 'package:flutter/material.dart';
import 'app.dart';
import 'supabase/client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase with env vars passed at build time
  await initSupabase();

  // Initialize Firebase (for FCM push)
  // await initFirebase();

  runApp(const NotifierApp());
}
