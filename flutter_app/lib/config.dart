import 'package:supabase_flutter/supabase_flutter.dart';

/// Backend configuration — reads from Supabase app_config when available.
/// Falls back to local IP for development.
class BackendConfig {
  static String? _tunnelUrl;  // Set by AppConfigService

  /// The base URL of the detection backend API.
  static String get baseUrl {
    if (_tunnelUrl != null && _tunnelUrl!.isNotEmpty) return _tunnelUrl!;
    return 'http://192.168.100.20:8001';
  }

  /// Set by AppConfigService after loading from Supabase.
  static set tunnelUrl(String? url) => _tunnelUrl = url;

  /// Construct a full snapshot URL from a stored relative or absolute path.
  /// Includes auth token for protected endpoints.
  static String snapshotUrl(String storedPath) {
    if (storedPath.startsWith('/app/snapshots/')) {
      storedPath = storedPath.replaceFirst('/app/snapshots/', '');
    }
    // Append auth token for protected snapshot endpoints
    final token = _getAuthToken();
    if (token != null) {
      return '$baseUrl/api/snapshots/$storedPath?token=$token';
    }
    return '$baseUrl/api/snapshots/$storedPath';
  }

  /// Construct a live camera snapshot URL.
  static String liveSnapshotUrl(String cameraAlias) {
    return '$baseUrl/api/cameras/$cameraAlias/snapshot';
  }

  static String? _getAuthToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }
}
