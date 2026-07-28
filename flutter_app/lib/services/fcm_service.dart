import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';

/// Firebase Cloud Messaging (FCM) service — handles registration + incoming pushes.
class FcmService {
  static final FcmService _instance = FcmService._();
  factory FcmService() => _instance;
  FcmService._();

  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _pendingToken;

  bool isReady = false;
  String? initError;
  String registerStatus = 'Not started';
  DateTime? lastAttempt;

  /// Stream that notifies when status changes.
  final statusController = StreamController<String>.broadcast();
  Stream<String> get onStatusChange => statusController.stream;

  void _setStatus(String s) {
    registerStatus = s;
    statusController.add(s);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('Notification permission denied');
      }
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'codebridge-alerts',
          'Camera Alerts',
          description: 'Push notifications from camera detections',
          importance: Importance.high,
        ),
      );
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true, badge: true, sound: true,
      announcement: true, criticalAlert: true,
    );

    _pendingToken = await messaging.getToken();
    isReady = true;
    debugPrint('FCM token obtained: ${_pendingToken?.substring(0, 20)}...');

    // Register if already logged in
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      register(session);
    }

    // Listen for auth changes
    Supabase.instance.client.auth.onAuthStateChange.listen((authState) {
      if (authState.session != null && _pendingToken != null) {
        register(authState.session!);
      }
    });

    // Token refresh
    messaging.onTokenRefresh.listen((newToken) {
      _pendingToken = newToken;
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) register(session);
    });

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_showNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((m) {});
  }

  /// Manual or automatic register — called from Settings button too.
  Future<void> register(Session session) async {
    if (_pendingToken == null) {
      _setStatus('No FCM token');
      return;
    }
    lastAttempt = DateTime.now();
    _setStatus('Registering...');

    try {
      // Insert directly into Supabase — no backend middleman needed
      final userId = session.user.id;
      debugPrint('FCM register: user=$userId, token=${_pendingToken!.substring(0, 20)}...');

      // Delete any old token for this device, then insert new one
      await supabase
          .from('device_tokens')
          .delete()
          .eq('token', _pendingToken!);

      final res = await supabase
          .from('device_tokens')
          .insert({
            'user_id': userId,
            'token': _pendingToken,
            'platform': 'android',
          });

      _setStatus('Registered ✅');
      debugPrint('FCM token registered ✅');
    } catch (e) {
      _setStatus('Error: $e');
      debugPrint('FCM register error: $e');
    }
  }

  void _showNotification(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'codebridge-alerts', 'Camera Alerts',
        importance: Importance.high, priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      n.title ?? 'Alert', n.body ?? '', details,
    );
  }

  void stop() {
    _localNotifications.cancelAll();
    statusController.close();
  }
}
