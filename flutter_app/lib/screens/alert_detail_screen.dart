import 'package:flutter/material.dart';

/// Full-screen view of an alert snapshot with pinch-to-zoom.
class AlertDetailScreen extends StatelessWidget {
  final String imageUrl;
  final String title;

  const AlertDetailScreen({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.image_not_supported,
                        color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    Text('Failed to load image',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white54)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
