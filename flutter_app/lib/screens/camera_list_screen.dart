import 'package:flutter/material.dart';
import '../supabase/client.dart';
import '../models/camera.dart';
import '../auth/auth_service.dart';
import '../widgets/camera_card.dart';
import 'alert_feed_screen.dart';
import 'login_screen.dart';

class CameraListScreen extends StatefulWidget {
  const CameraListScreen({super.key});

  @override
  State<CameraListScreen> createState() => _CameraListScreenState();
}

class _CameraListScreenState extends State<CameraListScreen> {
  final _auth = AuthService();
  List<Camera> _cameras = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    setState(() => _loading = true);
    try {
      final response = await supabase.from('cameras').select('*');
      final data = response as List<dynamic>;
      setState(() {
        _cameras = data.map((json) => Camera.fromJson(json as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load cameras: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Codebridge Notifier'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlertFeedScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cameras.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text('No cameras configured', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Contact Codebridge to add your first camera.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadCameras,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _cameras.length,
                    itemBuilder: (context, index) => CameraCard(camera: _cameras[index]),
                  ),
                ),
    );
  }
}
