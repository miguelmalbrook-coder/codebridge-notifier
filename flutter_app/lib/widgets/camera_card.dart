import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live preview thumbnail
          _LivePreview(cameraId: camera.id, cameraAlias: camera.alias, isOnline: camera.isOnline),
          // Camera info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      camera.isOnline ? Icons.videocam : Icons.videocam_off,
                      color: camera.isOnline ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(camera.alias,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                const SizedBox(height: 6),
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
              ],
            ),
          ),
        ],
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

/// Fetches and displays a live snapshot from the camera.
class _LivePreview extends StatefulWidget {
  final String cameraId;
  final String cameraAlias;
  final bool isOnline;

  const _LivePreview({required this.cameraId, required this.cameraAlias, required this.isOnline});

  @override
  State<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<_LivePreview> {
  late Future<Uint8List?> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _fetchPreview();
  }

  Future<Uint8List?> _fetchPreview() async {
    try {
      final session = supabase.auth.currentSession;
      if (session == null) return null;
      final url = '${BackendConfig.baseUrl}/api/cameras/${widget.cameraId}/preview?token=${session.accessToken}';
      final resp = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 8),
      );
      if (resp.statusCode == 200) return resp.bodyBytes;
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CameraDetailScreen(cameraAlias: widget.cameraAlias, cameraId: widget.cameraId),
          ),
        );
      },
      child: FutureBuilder<Uint8List?>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(
              snapshot.data!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            );
          }
          // Placeholder
          return Container(
            height: 140,
            width: double.infinity,
            color: Colors.grey[900],
            child: Center(
              child: widget.isOnline
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                    )
                  : Icon(Icons.videocam_off, color: Colors.grey[600], size: 40),
            ),
          );
        },
      ),
    );
  }
}
