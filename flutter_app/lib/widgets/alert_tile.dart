import 'package:flutter/material.dart';
import '../models/alert.dart';

class AlertTile extends StatelessWidget {
  final Alert alert;

  const AlertTile({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _iconForClass(alert.className);
    final color = _colorForClass(alert.className);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          alert.className.toUpperCase(),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${alert.cameraId} · ${alert.confidenceLabel}', style: theme.textTheme.bodySmall),
            Text(_formatTime(alert.seenAt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        trailing: alert.snapshotUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  alert.snapshotUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
                ),
              )
            : null,
      ),
    );
  }

  IconData _iconForClass(String className) {
    switch (className.toLowerCase()) {
      case 'person':
        return Icons.person;
      case 'car':
        return Icons.directions_car;
      case 'cat':
        return Icons.pets;
      case 'dog':
        return Icons.pets;
      default:
        return Icons.notification_important;
    }
  }

  Color _colorForClass(String className) {
    switch (className.toLowerCase()) {
      case 'person':
        return Colors.orange;
      case 'car':
        return Colors.blue;
      case 'cat':
      case 'dog':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
