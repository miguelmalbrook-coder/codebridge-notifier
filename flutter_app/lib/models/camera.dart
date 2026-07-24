class Camera {
  final String id;
  final String alias;
  final String status; // online, offline, error
  final DateTime? lastSeen;
  final DateTime createdAt;

  Camera({
    required this.id,
    required this.alias,
    required this.status,
    this.lastSeen,
    required this.createdAt,
  });

  factory Camera.fromJson(Map<String, dynamic> json) {
    return Camera(
      id: json['id'] as String,
      alias: json['alias'] as String? ?? 'Camera',
      status: json['status'] as String? ?? 'offline',
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isOnline => status == 'online';
}
