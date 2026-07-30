import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Singleton service that tracks whether YOLO monitoring is active or paused.
/// Polls the backend every 10 seconds and exposes a ValueNotifier for UI.
class MonitoringService {
  static final MonitoringService _instance = MonitoringService._();
  factory MonitoringService() => _instance;
  MonitoringService._();

  final ValueNotifier<bool> isActive = ValueNotifier(true);
  bool _polling = false;
  Timer? _pollTimer;

  bool get isMonitoring => isActive.value;

  /// Start polling monitoring status.
  void startPolling() {
    if (_polling) return;
    _polling = true;
    _check(); // Immediate check
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  /// Stop polling.
  void stopPolling() {
    _polling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _check() async {
    try {
      final resp = await http.get(
        Uri.parse('${BackendConfig.baseUrl}/api/monitoring/status'),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final paused = data['paused'] as bool? ?? false;
        isActive.value = !paused;
      }
    } catch (_) {
      // If we can't reach backend, assume active (don't alarm user)
    }
  }

  /// Pause monitoring.
  Future<bool> pause() async {
    try {
      final resp = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/api/monitoring/pause'),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        isActive.value = false;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Resume monitoring.
  Future<bool> resume() async {
    try {
      final resp = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/api/monitoring/resume'),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        isActive.value = true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Toggle monitoring state. Returns new state.
  Future<bool> toggle() async {
    if (isActive.value) {
      await pause();
    } else {
      await resume();
    }
    return isActive.value;
  }
}
