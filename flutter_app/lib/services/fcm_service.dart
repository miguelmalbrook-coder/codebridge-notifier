import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Firebase Cloud Messaging (FCM) service — handles registration + incoming pushes.
///
/// WhatsApp-level push reliability. Works even when app is killed.
class FcmService {
  static final FcmService _instance = FcmService._();
  factory FcmService() => _instance;
  FcmService._();

  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _pendingToken;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Init local notifications for showing FCM messages
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // Create notification channel
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

    // Request permission
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: true,
      criticalAlert: true,
    );

    // Get FCM token
    _pendingToken = await messaging.getToken();
    debugPrint('FCM token: ${_pendingToken?.substring(0, 20)}...');

    // Try to register if session exists, otherwise wait for login
    _registerOrWait();

    // Listen for token refresh
    messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM token refreshed');
      _pendingToken = newToken;
      _registerOrWait();
    });

    // Handle foreground messages — show local notification
    FirebaseMessaging.onMessage.listen(_showFcmNotification);

    // Handle background message tap (app opened from notification)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle app opened from terminated state via notification
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Register token if session exists, otherwise subscribe to auth changes.
  void _registerOrWait() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && _pendingToken != null) {
      _registerToken(_pendingToken!);
    }
    // Listen for future auth changes
    Supabase.instance.client.auth.onAuthStateChange.listen((authState) {
      if (authState.session != null && _pendingToken != null) {
        _registerToken(_pendingToken!);
      }
    });
  }

  Future<void> _registerToken(String token) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final res = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/api/devices/register'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': token,
          'platform': 'android',
        }),
      );
      if (res.statusCode == 200) {
        debugPrint('FCM token registered ✅');
      } else {
        debugPrint('FCM token registration failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('FCM register error: $e');
    }
  }

  void _showFcmNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final title = notification.title ?? 'Codebridge Alert';
    final body = notification.body ?? '';

    final androidDetails = AndroidNotificationDetails(
      'codebridge-alerts',
      'Camera Alerts',
      channelDescription: 'Push notifications from camera detections',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    final details = NotificationDetails(android: androidDetails);

    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('FCM notification tapped: ${message.messageId}');
  }
}
