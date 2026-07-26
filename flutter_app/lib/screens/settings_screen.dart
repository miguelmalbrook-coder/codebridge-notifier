import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../auth/auth_service.dart';
import '../config.dart';
import '../supabase/client.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();

  String _mode = 'yolo';
  String _model = 'yolo11s.pt';
  double _confidence = 0.4;
  int _cooldown = 15;
  List<String> _availableModels = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse('${BackendConfig.baseUrl}/api/settings'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _mode = data['mode'] as String? ?? 'yolo';
          _model = data['model'] as String? ?? 'yolo11s.pt';
          _confidence = (data['confidence'] as num?)?.toDouble() ?? 0.4;
          _cooldown = (data['cooldown'] as num?)?.toInt() ?? 15;
          _availableModels = (data['available_models'] as List<dynamic>?)
                  ?.cast<String>() ??
              [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load settings: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      final session = supabase.auth.currentSession;
      if (session == null) return;

      final res = await http.put(
        Uri.parse('${BackendConfig.baseUrl}/api/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': session.accessToken,
        },
        body: jsonEncode({
          'mode': _mode,
          'model': _model,
          'confidence': _confidence,
          'cooldown': _cooldown,
        }),
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Settings saved'),
                backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(res.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Detection Mode
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Detection Mode',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'yolo', label: Text('YOLO')),
                            ButtonSegment(
                                value: 'motion', label: Text('Motion')),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (v) {
                            setState(() => _mode = v.first);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _mode == 'yolo'
                              ? 'Pure YOLO on every frame (more CPU)'
                              : 'Motion detection gates YOLO (saves CPU)',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // YOLO Model
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOLO Model',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _availableModels.contains(_model)
                              ? _model
                              : _availableModels.isNotEmpty
                                  ? _availableModels.first
                                  : null,
                          items: _availableModels
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _model = v);
                            }
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Applies after next camera refresh (~30s)',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Confidence threshold
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Confidence Threshold',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _confidence,
                                min: 0.05,
                                max: 0.95,
                                divisions: 18,
                                label: '${(_confidence * 100).round()}%',
                                onChanged: (v) {
                                  setState(() => _confidence = v);
                                },
                              ),
                            ),
                            SizedBox(
                              width: 48,
                              child: Text(
                                '${(_confidence * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Lower = more detections (more false alarms)',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Cooldown
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alert Cooldown',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _cooldown.toDouble(),
                                min: 1,
                                max: 120,
                                divisions: 119,
                                label: '${_cooldown}s',
                                onChanged: (v) {
                                  setState(() => _cooldown = v.round());
                                },
                              ),
                            ),
                            SizedBox(
                              width: 48,
                              child: Text(
                                '${_cooldown}s',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Min seconds between same-class alerts',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Save button
                FilledButton.icon(
                  onPressed: _saving ? null : _saveSettings,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save Settings'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 24),

                // Connection info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connection',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _row('Backend', BackendConfig.baseUrl),
                        const SizedBox(height: 4),
                        _row('User',
                            _auth.currentUser?.email ?? 'unknown'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Sign out
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Sign Out'),
                    onTap: () async {
                      await _auth.signOut();
                      if (context.mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Version
                Center(
                  child: Text(
                    'Codebridge Notifier v0.2.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Flexible(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
