import 'dart:async';

import 'package:flutter/material.dart';
import '../config.dart';

/// Camera live view with periodic snapshot refresh.
class CameraDetailScreen extends StatefulWidget {
  final String cameraAlias;

  const CameraDetailScreen({super.key, required this.cameraAlias});

  @override
  State<CameraDetailScreen> createState() => _CameraDetailScreenState();
}

class _CameraDetailScreenState extends State<CameraDetailScreen> {
  /// Backend URL from shared config
  String get _backendUrl => BackendConfig.baseUrl;

  Timer? _refreshTimer;
  int _refreshKey = 0; // Increment to force Image widget reload

  @override
  void initState() {
    super.initState();
    // Refresh snapshot every 3 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() => _refreshKey++);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String get _snapshotUrl =>
      '$_backendUrl/api/cameras/${widget.cameraAlias}/snapshot?t=$_refreshKey';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.cameraAlias)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Live snapshot
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                _snapshotUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 8),
                        Text('Loading...',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Camera info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Camera Info', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _infoRow('Name', widget.cameraAlias),
                    _infoRow('Status', 'Online'),
                    _infoRow('Snapshot', 'Refreshes every 3s'),
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
