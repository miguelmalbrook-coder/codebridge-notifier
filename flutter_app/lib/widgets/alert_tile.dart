import 'package:flutter/material.dart';
import '../config.dart';
import '../models/alert.dart';
import '../screens/alert_detail_screen.dart';

class AlertTile extends StatelessWidget {
  final Alert alert;

  const AlertTile({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _iconForClass(alert.className);
    final color = _colorForClass(alert.className);

    // Build snapshot URL from relative path (with cache-busting)
    final hasSnapshot = alert.snapshotUrl.isNotEmpty;
    final snapBase =
        hasSnapshot ? BackendConfig.snapshotUrl(alert.snapshotUrl) : null;
    // Add cache-busting param so thumbnails refresh on each rebuild
    final fullSnapUrl = snapBase != null
        ? '$snapBase&_cb=${alert.seenAt.millisecondsSinceEpoch}'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.className.toUpperCase(),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${alert.cameraId} · ${alert.confidenceLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatRelative(alert.seenAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _formatAbsolute(alert.seenAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Snapshot image
          if (fullSnapUrl != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlertDetailScreen(
                      imageUrl: fullSnapUrl,
                      title: '${alert.className} @ ${alert.cameraId}',
                    ),
                  ),
                );
              },
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  fullSnapUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_not_supported,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 4),
                            Text('No snapshot',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
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

  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final local = dt.isUtc ? dt.toLocal() : dt;
    final diff = now.difference(local);
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatAbsolute(DateTime dt) {
    final local = dt.isUtc ? dt.toLocal() : dt;
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final y = local.year.toString().substring(2);
    return '${h}:${m}hrs on $d.$mo.$y';
  }
}
