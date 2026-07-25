class Camera {
  final String id;
  final String alias;
  final String rtspUrl;
  final String status; // online, offline, error
  final DateTime? lastSeen;
  final DateTime createdAt;

  Camera({
    required this.id,
    required this.alias,
    this.rtspUrl = '',
    required this.status,
    this.lastSeen,
    required this.createdAt,
  });

  factory Camera.fromJson(Map<String, dynamic> json) {
    return Camera(
      id: json['id'] as String,
      alias: json['alias'] as String? ?? 'Camera',
      rtspUrl: json['rtsp_url'] as String? ?? '',
      status: json['status'] as String? ?? 'offline',
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alias': alias,
      'rtsp_url': rtspUrl,
      'status': status,
    };
  }

  bool get isOnline => status == 'online';
}
