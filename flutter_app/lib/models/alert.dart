class Alert {
  final String id;
  final String cameraId;
  final String className;
  final double confidence;
  final String snapshotUrl;
  final DateTime seenAt;

  Alert({
    required this.id,
    required this.cameraId,
    required this.className,
    required this.confidence,
    required this.snapshotUrl,
    required this.seenAt,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as String,
      cameraId: json['camera_id'] as String? ?? '',
      className: json['class_name'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      snapshotUrl: json['snapshot_url'] as String? ?? '',
      seenAt: DateTime.parse(json['seen_at'] as String),
    );
  }

  String get confidenceLabel => '${(confidence * 100).round()}%';
}
