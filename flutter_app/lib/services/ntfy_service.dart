import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import 'app_config_service.dart';

/// Subscribes to ntfy topic and shows local notifications.
class NtfyService {
  static final NtfyService _instance = NtfyService._();
  factory NtfyService() => _instance;
  NtfyService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _pollTimer;
  bool _initialized = false;
  String? _lastMessageId;

  /// Initialize local notifications + request permissions + start polling.
  Future<void> start() async {
    if (_initialized) return;
    _initialized = true;

    // Request notification permission on Android 13+
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('Notification permission denied');
      }
    }

    // Init local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
      },
    );

    // Create notification channel for Android
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
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

    // Start polling ntfy
    _pollNtfy();
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _pollNtfy() {
    // Poll immediately, then every 15 seconds
    _fetchAlerts();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchAlerts());
  }

  String _getNtfyBaseUrl() {
    return AppConfigService().ntfyUrl;
  }

  /// Returns an ISO-8601 timestamp from 5 minutes ago for ntfy polling.
  String _defaultSince() {
    return DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String();
  }

  Future<void> _fetchAlerts() async {
    try {
      // Use ntfy tunnel URL from app_config, or fall back to local network
      final ntfyHost = _getNtfyBaseUrl();
      final sinceParam = _lastMessageId != null
          ? '&since=$_lastMessageId'
          : '&since=${_defaultSince()}';
      final url = Uri.parse('$ntfyHost/codebridge-alerts/json?poll=1$sinceParam');
      final res = await http.get(url).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final lines = res.body.split('\n').where((l) => l.trim().isNotEmpty);
        for (final line in lines) {
          try {
            final msg = jsonDecode(line) as Map<String, dynamic>;
            final id = msg['id'] as String?;
            if (id != null && id != _lastMessageId) {
              _lastMessageId = id;
              await _showNotification(msg);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('ntfy poll error: $e');
    }
  }

  Future<void> _showNotification(Map<String, dynamic> msg) async {
    final title = msg['title'] as String? ?? 'Codebridge Alert';
    final message = msg['message'] as String? ?? '';

    const androidDetails = AndroidNotificationDetails(
      'codebridge-alerts',
      'Camera Alerts',
      channelDescription: 'Push notifications from camera detections',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      message,
      details,
    );
  }
}
