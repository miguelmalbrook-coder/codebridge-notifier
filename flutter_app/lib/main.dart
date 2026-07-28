import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'services/app_config_service.dart';
import 'services/ntfy_service.dart';
import 'services/fcm_service.dart';
import 'supabase/client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase with env vars passed at build time
  await initSupabase();

  // Load app config FIRST so ntfy has the correct tunnel URL
  await AppConfigService().load();

  // Initialize Firebase with explicit options
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyC9B8WThqs86Ib3OuEPpVjxM5mPZ2J8SJI',
        appId: '1:543962529025:android:cb90ee9a213c3efcc32f00',
        messagingSenderId: '543962529025',
        projectId: 'yolonotifier',
        storageBucket: 'yolonotifier.firebasestorage.app',
      ),
    );
    await FcmService().init();
  } catch (e) {
    debugPrint('Firebase init error: $e');
    FcmService().initError = e.toString();
  }

  // Start ntfy polling (uses correct URL from AppConfigService)
  await NtfyService().start();

  runApp(const NotifierApp());
}
