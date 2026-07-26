import 'package:flutter/material.dart';
import '../models/camera.dart';
import '../screens/camera_detail_screen.dart';
import '../supabase/client.dart';
import 'camera_edit_dialog.dart';

class CameraCard extends StatelessWidget {
  final Camera camera;
  final VoidCallback? onChanged;

  const CameraCard({super.key, required this.camera, this.onChanged});

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
        title: Text(camera.alias,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
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
                Text(camera.isOnline ? 'Online' : 'Offline',
                    style: theme.textTheme.bodySmall),
                if (camera.lastSeen != null) ...[
                  const SizedBox(width: 16),
                  Text('Last seen: ${_formatTime(camera.lastSeen!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
            if (camera.rtspUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                camera.rtspUrl,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
        onLongPress: () => _editCamera(context),
      ),
    );
  }

  Future<void> _editCamera(BuildContext context) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => CameraEditDialog(camera: camera),
    );
    if (result == null || !context.mounted) return;

    try {
      await supabase
          .from('cameras')
          .update({'alias': result['alias'], 'rtsp_url': result['url']})
          .eq('id', camera.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera updated'),
            backgroundColor: Colors.green,
          ),
        );
        onChanged?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
