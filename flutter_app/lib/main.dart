import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'services/ntfy_service.dart';
import 'services/fcm_service.dart';
import 'supabase/client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase with env vars passed at build time
  await initSupabase();

  // Initialize Firebase (reads google-services.json automatically)
  try {
    await Firebase.initializeApp();
    await FcmService().init();
    debugPrint('Firebase + FCM initialized');
  } catch (e) {
    debugPrint('Firebase init error (non-fatal): $e');
  }

  // Start ntfy push notifications (fallback)
  await NtfyService().start();

  runApp(const NotifierApp());
}
