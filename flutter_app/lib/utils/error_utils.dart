/// Converts raw exceptions into user-friendly error messages.
String friendlyError(Object error) {
  final msg = error.toString();

  if (msg.contains('SocketException') || msg.contains('No address associated')) {
    return 'No internet connection. Check your WiFi or mobile data.';
  }
  if (msg.contains('TimeoutException') || msg.contains('timed out')) {
    return 'Connection timed out. Try again.';
  }
  if (msg.contains('ClientException')) {
    return 'Network error. Check your connection.';
  }
  if (msg.contains('HandshakeException') || msg.contains('SSL')) {
    return 'Secure connection failed.';
  }
  if (msg.contains('HttpException')) {
    return 'Server error. Try again later.';
  }
  if (msg.contains('FormatException')) {
    return 'Invalid response from server.';
  }

  // Generic fallback — short and clean
  return 'Something went wrong. Try again.';
}
