import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'app_config_service.dart';
import '../supabase/client.dart';

/// Subscribes to ntfy topic and shows local notifications.
/// Also listens to Supabase Realtime for instant alerts (more reliable).
class NtfyService {
  static final NtfyService _instance = NtfyService._();
  factory NtfyService() => _instance;
  NtfyService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _pollTimer;
  bool _initialized = false;
  String? _lastMessageId;
  dynamic _realtimeChannel;

  Future<void> start() async {
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
    await _plugin.initialize(initSettings);

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

    // Subscribe to Supabase Realtime for INSTANT alerts
    _subscribeRealtime();

    // Keep ntfy polling as fallback
    _pollNtfy();
  }

  void stop() {
    _pollTimer?.cancel();
    _realtimeChannel?.unsubscribe();
  }

  void _subscribeRealtime() {
    try {
      _realtimeChannel = supabase
          .channel('app-notifications')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'alerts',
            callback: (payload) {
              final newRecord = payload.newRecord as Map<String, dynamic>;
              final className = newRecord['class_name'] as String? ?? 'Something';
              final cameraId = newRecord['camera_id'] as String? ?? 'Camera';
              final confidence = (newRecord['confidence'] as num?)?.toDouble() ?? 0;
              _showLocalNotification(
                '🚨 ${className.toUpperCase()} detected',
                '$cameraId · ${(confidence * 100).round()}% confidence',
              );
            },
          )
          .subscribe();
      debugPrint('Realtime notification subscription active');
    } catch (e) {
      debugPrint('Realtime subscription error: $e');
    }
  }

  void _showLocalNotification(String title, String body) {
    const androidDetails = AndroidNotificationDetails(
      'codebridge-alerts',
      'Camera Alerts',
      channelDescription: 'Push notifications from camera detections',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  void _pollNtfy() {
    _fetchAlerts();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _fetchAlerts());
  }

  String _getNtfyBaseUrl() {
    return AppConfigService().ntfyUrl;
  }

  String _defaultSince() {
    return DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String();
  }

  Future<void> _fetchAlerts() async {
    try {
      final ntfyHost = _getNtfyBaseUrl();
      final sinceParam = _lastMessageId != null
          ? '&since=$_lastMessageId'
          : '&since=${_defaultSince()}';
      final url = Uri.parse('$ntfyHost/codebridge-alerts/json?poll=1$sinceParam');

      // Try old simple approach — might work if connection closes quickly
      final res = await http.get(url).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final lines = res.body.split('\n').where((l) => l.trim().isNotEmpty);
        for (final line in lines) {
          try {
            final msg = jsonDecode(line) as Map<String, dynamic>;
            if (msg['event'] == 'message') {
              final id = msg['id'] as String?;
              if (id != null && id != _lastMessageId) {
                _lastMessageId = id;
                final title = msg['title'] as String? ?? 'Codebridge Alert';
                final message = msg['message'] as String? ?? '';
                _showLocalNotification(title, message);
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      // Timeout is expected (ntfy holds connection open) — fallback to Realtime
      debugPrint('ntfy poll: $e (realtime handles it)');
    }
  }
}
