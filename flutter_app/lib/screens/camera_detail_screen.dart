import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Placeholder for live camera view.
/// Future: Replace with MJPEG stream player or WebRTC widget.
class CameraDetailScreen extends StatelessWidget {
  final String cameraAlias;

  const CameraDetailScreen({super.key, required this.cameraAlias});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(cameraAlias)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Live view placeholder
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text('Live View', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Coming soon', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Camera info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Camera Info', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _infoRow('Name', cameraAlias),
                    _infoRow('Status', 'Online'),
                    _infoRow('Type', 'RTSP (Hikvision)'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
