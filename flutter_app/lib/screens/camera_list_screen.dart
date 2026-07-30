import 'package:flutter/material.dart';
import '../supabase/client.dart';
import '../utils/error_utils.dart';
import '../models/camera.dart';
import '../widgets/camera_card.dart';
import '../widgets/camera_edit_dialog.dart';

class CameraListScreen extends StatefulWidget {
  const CameraListScreen({super.key});

  @override
  State<CameraListScreen> createState() => _CameraListScreenState();
}

class _CameraListScreenState extends State<CameraListScreen> {
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
      final response = await supabase
          .from('cameras')
          .select('*')
          .order('created_at', ascending: true);
      final data = response as List<dynamic>;
      setState(() {
        _cameras = data
            .map((json) => Camera.fromJson(json as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCamera() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const CameraEditDialog(),
    );
    if (result == null || !mounted) return;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await supabase.from('cameras').insert({
        'user_id': user.id,
        'alias': result['alias'],
        'rtsp_url': result['url'],
        'status': 'offline',
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera added!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadCameras();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_cameras.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No cameras configured',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first camera.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadCameras,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _cameras.length,
            itemBuilder: (context, index) => CameraCard(
              camera: _cameras[index],
              onChanged: _loadCameras,
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _addCamera,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
