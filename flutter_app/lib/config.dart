/// Backend configuration — change this when you set up a tunnel.
class BackendConfig {
  /// The base URL of the detection backend API.
  static const String baseUrl = 'http://192.168.100.20:8001';

  /// Construct a full snapshot URL from a stored relative or absolute path.
  ///
  /// Handles both old format ("/app/snapshots/cam/file.jpg") and
  /// new format ("cam/file.jpg").
  static String snapshotUrl(String storedPath) {
    if (storedPath.startsWith('/app/snapshots/')) {
      // Old format — extract the relative part after "/app/snapshots/"
      storedPath = storedPath.replaceFirst('/app/snapshots/', '');
    }
    return '$baseUrl/api/snapshots/$storedPath';
  }
}
