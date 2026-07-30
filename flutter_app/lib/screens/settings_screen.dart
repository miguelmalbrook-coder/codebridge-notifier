import 'dart:convert';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../auth/auth_service.dart';
import '../config.dart';
import '../supabase/client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/fcm_service.dart';
import '../services/monitoring_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  List<Map<String, dynamic>> _cameras = [];
  List<String> _availableModels = [];
  List<String> _availableTargets = [];
  bool _loading = true;
  bool _saving = false;
  String _appVersion = '';
  StreamSubscription? _fcmSub;
  String _fcmStatus = '';

  // Local slider state for smooth dragging (key = "cameraId_field")
  final Map<String, double> _localSliderValues = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadVersion();
    // Live-update FCM status
    _fcmSub = FcmService().onStatusChange.listen((s) {
      if (mounted) setState(() => _fcmStatus = s);
    });
    _fcmStatus = FcmService().registerStatus;
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = '0.9.0';
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    // Load cameras from Supabase (fast, direct connection)
    await _loadCameras();
    if (mounted) setState(() => _loading = false);
    // Load metadata from backend in background (may be slow through tunnel)
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final res = await http.get(Uri.parse('${BackendConfig.baseUrl}/api/settings'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _availableModels = (data['available_models'] as List<dynamic>?)?.cast<String>() ?? [];
          _availableTargets = (data['available_targets'] as List<dynamic>?)?.cast<String>() ?? [];
        });
      }
    } catch (e) {
      debugPrint('Failed to load meta: $e');
      // Set defaults if backend is unreachable
      if (mounted && _availableModels.isEmpty) {
        setState(() {
          _availableModels = ['yolo11n.pt', 'yolo11s.pt', 'yolo11m.pt', 'yolo11l.pt', 'yolo11x.pt'];
          _availableTargets = ['person', 'car', 'cat', 'dog', 'truck', 'bus', 'motorcycle', 'bicycle'];
        });
      }
    }
  }

  Future<void> _loadCameras() async {
    try {
      final response = await supabase
          .from('cameras')
          .select('id, alias, detection_mode, model, confidence, cooldown_seconds, targets, motion_sensitivity, class_confidences')
          .order('created_at');
      setState(() {
        _cameras = (response as List<dynamic>).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      debugPrint('Failed to load cameras: $e');
    }
  }

  Future<void> _saveCameraSetting(String cameraId, String field, dynamic value) async {
    try {
      await supabase.from('cameras').update({field: value}).eq('id', cameraId);
      final idx = _cameras.indexWhere((c) => c['id'] == cameraId);
      if (idx != -1) setState(() => _cameras[idx][field] = value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Per-Camera Settings
                Row(
                  children: [
                    Icon(Icons.videocam, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Per-Camera Settings', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Configure each camera independently',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (_cameras.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.videocam_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text('No cameras found', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 4),
                            Text('Add a camera in the Cameras tab first.',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ..._cameras.map((cam) => _cameraCard(cam, theme)),
                const SizedBox(height: 24),

                // ── Monitoring Toggle ──
                ListenableBuilder(
                  listenable: MonitoringService().isActive,
                  builder: (context, _) {
                    final isOn = MonitoringService().isMonitoring;
                    return Card(
                      child: SwitchListTile(
                        secondary: Icon(
                          isOn ? Icons.monitor : Icons.pause_circle_outline,
                          color: isOn ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          'Monitoring',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isOn ? null : Colors.red,
                          ),
                        ),
                        subtitle: Text(
                          isOn ? 'YOLO detection is active' : 'Paused — no alerts will be sent',
                          style: TextStyle(
                            color: isOn ? theme.colorScheme.onSurfaceVariant : Colors.red,
                          ),
                        ),
                        value: isOn,
                        onChanged: (val) async {
                          if (val) {
                            await MonitoringService().resume();
                          } else {
                            await MonitoringService().pause();
                          }
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Connection
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connection', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _row('Backend', BackendConfig.baseUrl),
                        const SizedBox(height: 4),
                        _row('User', _auth.currentUser?.email ?? 'unknown'),
                        const SizedBox(height: 4),
                        _row('FCM', FcmService().isReady ? 'Ready ✅' : 'Not ready ❌'),
                        if (!FcmService().isReady) ...[
                          const SizedBox(height: 4),
                          Text(
                            FcmService().initError ?? 'Firebase init failed.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text('Status: $_fcmStatus',
                            style: theme.textTheme.bodySmall),
                        if (_fcmStatus != 'Registered ✅' && FcmService().isReady) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final session = Supabase.instance.client.auth.currentSession;
                                if (session != null) {
                                  await FcmService().register(session);
                                }
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retry Registration'),
                            ),
                          ),
                        ],
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
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text('Codebridge Notifier v$_appVersion', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
    );
  }

  Widget _cameraCard(Map<String, dynamic> cam, ThemeData theme) {
    final mode = cam['detection_mode'] as String? ?? 'yolo';
    final model = cam['model'] as String? ?? 'yolo11s.pt';
    final conf = (cam['confidence'] as num?)?.toDouble() ?? 0.4;
    final cooldown = (cam['cooldown_seconds'] as num?)?.toInt() ?? 15;
    final targets = (cam['targets'] as List<dynamic>?)?.cast<String>() ?? ['person', 'car', 'cat', 'dog'];
    final motionSensitivity = (cam['motion_sensitivity'] as num?)?.toDouble() ?? 0.001;
    final camId = cam['id'] as String;
    final alias = cam['alias'] as String? ?? 'Unknown';
    final displayConf = (conf * 100).toStringAsFixed(0);

    final isOff = mode == 'off';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          isOff ? Icons.power_settings_new : (mode == 'yolo' ? Icons.smart_toy : Icons.motion_photos_on),
          color: isOff ? Colors.grey : theme.colorScheme.primary,
        ),
        title: Text(alias, style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isOff ? Colors.grey : null,
        )),
        subtitle: Text(isOff ? 'Detection OFF' : '$mode · ${displayConf}% · ${targets.join(", ")}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isOff ? Colors.grey : null,
            )),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Master toggle ──
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(isOff ? 'YOLO Detection: OFF' : 'YOLO Detection: ON',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isOff ? Colors.red : Colors.green,
                    )),
                  subtitle: Text(isOff ? 'No detections will fire for this camera' : 'Detections active'),
                  value: !isOff,
                  onChanged: (v) {
                    _saveCameraSetting(camId, 'detection_mode', v ? 'yolo' : 'off');
                  },
                ),
                const Divider(),
                const SizedBox(height: 8),

                // Mode (only when ON)
                if (!isOff) ...[
                  _label('Detection Mode', theme),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'yolo', label: Text('YOLO')),
                      ButtonSegment(value: 'motion', label: Text('Motion')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => _saveCameraSetting(camId, 'detection_mode', v.first),
                  ),
                ],
                const SizedBox(height: 16),

                // ── YOLO-specific settings (hidden when OFF) ──
                if (!isOff) ...[
                // Model
                _label('YOLO Model', theme),
                DropdownButtonFormField<String>(
                  value: _availableModels.contains(model) ? model : _availableModels.firstOrNull,
                  items: _availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) { if (v != null) _saveCameraSetting(camId, 'model', v); },
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                ),
                const SizedBox(height: 16),

                // Cooldown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _label('Cooldown', theme),
                    Text('${cooldown}s', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: (_localSliderValues['${camId}_cooldown'] ?? cooldown.toDouble()),
                  min: 1, max: 120, divisions: 119,
                  onChanged: (v) {
                    setState(() => _localSliderValues['${camId}_cooldown'] = v);
                  },
                  onChangeEnd: (v) {
                    _localSliderValues.remove('${camId}_cooldown');
                    _saveCameraSetting(camId, 'cooldown_seconds', v.round());
                  },
                ),

                // Motion sensitivity (only relevant in motion mode)
                if (mode == 'motion') ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _label('Motion Sensitivity', theme),
                      Text('${(motionSensitivity * 100).toStringAsFixed(2)}%', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: (_localSliderValues['${camId}_motion'] ?? motionSensitivity),
                    min: 0.0001, max: 0.01, divisions: 99,
                    onChanged: (v) {
                      setState(() => _localSliderValues['${camId}_motion'] = v);
                    },
                    onChangeEnd: (v) {
                      _localSliderValues.remove('${camId}_motion');
                      _saveCameraSetting(camId, 'motion_sensitivity', double.parse(v.toStringAsFixed(4)));
                    },
                  ),
                  Text('Lower = more sensitive', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                ],

                // Targets + Per-Class Confidence
                const SizedBox(height: 12),
                _label('Detection Targets & Confidence', theme),
                const SizedBox(height: 8),

                // Selected targets with confidence sliders
                ..._availableTargets.where((t) => targets.contains(t)).map((t) {
                  final classConfs = Map<String, double>.from(
                    (cam['class_confidences'] as Map<dynamic, dynamic>?)
                            ?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ??
                        {},
                  );
                  final classConf = classConfs[t];
                  final currentConf = classConf ?? conf;
                  final pct = (currentConf * 100).round();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Chip(
                              label: Text(t, style: const TextStyle(fontSize: 13)),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                final updated = List<String>.from(targets);
                                updated.remove(t);
                                final newConfs = Map<String, double>.from(classConfs);
                                newConfs.remove(t);
                                _saveCameraSetting(camId, 'class_confidences', newConfs);
                                _saveCameraSetting(camId, 'targets', updated);
                              },
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: (_localSliderValues['${camId}_conf_$t'] ?? currentConf),
                                min: 0.05,
                                max: 0.95,
                                divisions: 18,
                                label: '${(_localSliderValues['${camId}_conf_$t'] ?? currentConf) * 100 ~/ 1}%',
                                onChanged: (v) {
                                  setState(() => _localSliderValues['${camId}_conf_$t'] = v);
                                },
                                onChangeEnd: (v) {
                                  _localSliderValues.remove('${camId}_conf_$t');
                                  final newConfs = Map<String, double>.from(classConfs);
                                  newConfs[t] = double.parse(v.toStringAsFixed(2));
                                  _saveCameraSetting(camId, 'class_confidences', newConfs);
                                },
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${((_localSliderValues['${camId}_conf_$t'] ?? currentConf) * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                // Unselected targets (add via chips)
                if (_availableTargets.any((t) => !targets.contains(t))) ...[
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Text('Add target:', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _availableTargets.where((t) => !targets.contains(t)).map((t) {
                      return FilterChip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        selected: false,
                        onSelected: (_) {
                          final updated = List<String>.from(targets);
                          updated.add(t);
                          _saveCameraSetting(camId, 'targets', updated);
                        },
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ], // end if (!isOff)
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Flexible(child: Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
