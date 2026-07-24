import 'package:flutter/material.dart';
import '../models/camera.dart';
import '../screens/camera_detail_screen.dart';

class CameraCard extends StatelessWidget {
  final Camera camera;

  const CameraCard({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          camera.isOnline ? Icons.videocam : Icons.videocam_off,
          color: camera.isOnline ? Colors.green : Colors.grey,
          size: 32,
        ),
        title: Text(camera.alias, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: camera.isOnline ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 6),
                Text(camera.isOnline ? 'Online' : 'Offline', style: theme.textTheme.bodySmall),
                if (camera.lastSeen != null) ...[
                  const SizedBox(width: 16),
                  Text('Last seen: ${_formatTime(camera.lastSeen!)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraDetailScreen(cameraAlias: camera.alias),
            ),
          );
        },
      ),
    );
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
