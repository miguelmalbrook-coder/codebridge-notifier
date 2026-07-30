import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../supabase/client.dart';

/// Camera live view with real-time YOLO AR overlay and interactive heatmap.
class CameraDetailScreen extends StatefulWidget {
  final String cameraAlias;
  final String cameraId;

  const CameraDetailScreen({super.key, required this.cameraAlias, required this.cameraId});

  @override
  State<CameraDetailScreen> createState() => _CameraDetailScreenState();
}

class _CameraDetailScreenState extends State<CameraDetailScreen> {
  String get _backendUrl => BackendConfig.baseUrl;

  Timer? _refreshTimer;
  int _refreshKey = 0;
  bool _arOverlay = false;
  bool _showHeatmap = false;
  Map<String, dynamic>? _heatmapData;

  // AR session state
  Timer? _arPollTimer;
  Uint8List? _arFrame;
  List<Map<String, dynamic>> _arDetections = [];
  bool _arLoading = false;
  Set<String> _arTargets = {'person', 'car', 'cat', 'dog'};

  static const _allClasses = ['person', 'car', 'cat', 'dog', 'truck', 'bus', 'motorcycle', 'bicycle'];
  static const _classColors = {
    'person': Colors.blue,
    'car': Colors.orange,
    'cat': Colors.purple,
    'dog': Colors.green,
    'truck': Colors.red,
    'bus': Colors.teal,
    'motorcycle': Colors.pink,
    'bicycle': Colors.indigo,
  };

  String? get _sessionToken => supabase.auth.currentSession?.accessToken;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_arOverlay) setState(() => _refreshKey++);
    });
    _loadHeatmap();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _arPollTimer?.cancel();
    super.dispose();
  }

  // ── AR Mode ──────────────────────────────────────

  void _startArSession() {
    _arOverlay = true;
    _arLoading = true;
    _arFrame = null;
    _arDetections = [];
    setState(() {});
    _pollArFrame();
    // Poll at ~500ms for smooth AR (2 fps is enough for detection display)
    _arPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollArFrame());
  }

  void _stopArSession() {
    _arOverlay = false;
    _arPollTimer?.cancel();
    _arPollTimer = null;
    _arFrame = null;
    _arDetections = [];
    setState(() {});
  }

  Future<void> _pollArFrame() async {
    if (!_arOverlay || !mounted) return;

    try {
      final url = '$_backendUrl/api/cameras/${widget.cameraId}/detect';
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'targets': _arTargets.toList()}),
      ).timeout(const Duration(seconds: 3));

      if (resp.statusCode == 200 && mounted) {
        // Parse detections from header
        final detHeader = resp.headers['x-detections'];
        List<Map<String, dynamic>> dets = [];
        if (detHeader != null) {
          final decoded = jsonDecode(detHeader) as List;
          dets = decoded.cast<Map<String, dynamic>>();
        }
        setState(() {
          _arFrame = resp.bodyBytes;
          _arDetections = dets;
          _arLoading = false;
        });
      } else if (mounted && resp.statusCode == 404) {
        // No frame yet — keep loading
        setState(() => _arLoading = true);
      }
    } catch (e) {
      // Silently retry on next tick
    }
  }

  void _toggleArClass(String cls) {
    setState(() {
      if (_arTargets.contains(cls)) {
        _arTargets.remove(cls);
      } else {
        _arTargets.add(cls);
      }
    });
    // Immediately poll with new targets
    _pollArFrame();
  }

  // ── Heatmap ──────────────────────────────────────

  String get _imageUrl {
    final token = _sessionToken ?? '';
    return '$_backendUrl/api/cameras/${widget.cameraAlias}/snapshot?token=$token&t=$_refreshKey';
  }

  Future<void> _loadHeatmap() async {
    try {
      final session = supabase.auth.currentSession;
      if (session == null) return;
      final url = '$_backendUrl/api/cameras/${widget.cameraId}/heatmap?hours=24';
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 && mounted) {
        setState(() => _heatmapData = jsonDecode(resp.body));
      }
    } catch (e) {
      // Silently fail
    }
  }

  void _showAlertsForHour(int hour, String? selectedClass) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AlertsForHourSheet(
        cameraId: widget.cameraId,
        cameraAlias: widget.cameraAlias,
        hour: hour,
        selectedClass: selectedClass,
        backendUrl: _backendUrl,
        sessionToken: _sessionToken ?? '',
      ),
    );
  }

  // ── Build ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cameraAlias),
        actions: [
          IconButton(
            icon: Icon(_arOverlay ? Icons.smart_toy : Icons.smart_toy_outlined),
            color: _arOverlay ? Colors.amber : null,
            tooltip: 'AR Detection',
            onPressed: () {
              if (_arOverlay) {
                _stopArSession();
              } else {
                _startArSession();
              }
            },
          ),
          IconButton(
            icon: Icon(_showHeatmap ? Icons.map : Icons.map_outlined),
            color: _showHeatmap ? Colors.orange : null,
            tooltip: 'Activity Heatmap',
            onPressed: () {
              setState(() => _showHeatmap = !_showHeatmap);
              if (_showHeatmap && _heatmapData == null) _loadHeatmap();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Live view / AR view ──
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        height: 300,
                        width: double.infinity,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: _arOverlay ? _buildArView(theme) : _buildSnapshotView(theme),
                      ),
                      if (_arOverlay)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.smart_toy, size: 14, color: Colors.black),
                                const SizedBox(width: 4),
                                Text(
                                  'AR · ${_arDetections.length} detected',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                  // ── AR class toggle buttons ──
                  if (_arOverlay) _buildArClassBar(theme),

                  // ── Heatmap ──
                  if (_showHeatmap)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildHeatmap(theme),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotView(ThemeData theme) {
    return Image.network(
      _imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('Camera offline', style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArView(ThemeData theme) {
    if (_arLoading && _arFrame == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(height: 12),
            Text('Starting AR detection...', style: TextStyle(color: Colors.amber)),
          ],
        ),
      );
    }

    if (_arFrame != null) {
      return Image.memory(
        _arFrame!,
        fit: BoxFit.cover,
        gaplessPlayback: true, // Prevents flicker between frames
      );
    }

    // Fallback: show live snapshot while waiting
    return Image.network(
      _imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator(color: Colors.amber));
      },
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Icon(Icons.videocam_off, size: 48, color: Colors.grey),
        );
      },
    );
  }

  Widget _buildArClassBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.8),
        border: Border(top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detection Classes',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _allClasses.map((cls) {
              final isActive = _arTargets.contains(cls);
              final color = _classColors[cls] ?? Colors.grey;
              return FilterChip(
                label: Text(cls, style: TextStyle(
                  fontSize: 12,
                  color: isActive ? Colors.white : color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                )),
                selected: isActive,
                onSelected: (_) => _toggleArClass(cls),
                selectedColor: color,
                checkmarkColor: Colors.white,
                avatar: isActive
                    ? null
                    : Icon(_iconForClass(cls), size: 16, color: color),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to toggle · ${_arTargets.length} active',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  IconData _iconForClass(String cls) {
    switch (cls) {
      case 'person': return Icons.person;
      case 'car': return Icons.directions_car;
      case 'cat': case 'dog': return Icons.pets;
      case 'truck': return Icons.local_shipping;
      case 'bus': return Icons.directions_bus;
      case 'motorcycle': return Icons.two_wheeler;
      case 'bicycle': return Icons.pedal_bike;
      default: return Icons.help_outline;
    }
  }

  Widget _buildHeatmap(ThemeData theme) {
    if (_heatmapData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = _heatmapData!['total_detections'] ?? 0;
    final classes = List<String>.from(_heatmapData!['classes'] ?? []);
    final heatmap = Map<String, dynamic>.from(_heatmapData!['heatmap'] ?? {});

    if (total == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(children: [
                const Icon(Icons.bar_chart, size: 20),
                const SizedBox(width: 8),
                Text('Activity (24h)', style: theme.textTheme.titleMedium),
              ]),
              const SizedBox(height: 16),
              const Text('No detections yet', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    int maxCount = 0;
    for (final cls in classes) {
      final classData = List<Map<String, dynamic>>.from(heatmap[cls] ?? []);
      for (final h in classData) {
        final count = h['count'] as int;
        if (count > maxCount) maxCount = count;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, size: 20),
                const SizedBox(width: 8),
                Text('Activity (24h)', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('$total detections', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: classes.map((cls) {
                final color = _classColors[cls] ?? Colors.grey;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 4),
                    Text(cls, style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (hour) {
                  int hourTotal = 0;
                  for (final cls in classes) {
                    final classData = List<Map<String, dynamic>>.from(heatmap[cls] ?? []);
                    if (hour < classData.length) {
                      hourTotal += classData[hour]['count'] as int;
                    }
                  }
                  final height = maxCount > 0 ? (hourTotal / maxCount) * 120 : 0.0;
                  final isNow = hour == DateTime.now().hour;

                  return Expanded(
                    child: GestureDetector(
                      onTap: hourTotal > 0 ? () => _showAlertsForHour(hour, null) : null,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: height.clamp(4, 120),
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: isNow ? Colors.amber : Colors.orange.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: hourTotal > 0
                                ? Center(
                                    child: Text(
                                      '$hourTotal',
                                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  )
                                : null,
                          ),
                          if (hour % 3 == 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${hour}h', style: const TextStyle(fontSize: 9)),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Text('Tap a bar to see screenshots', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            ...classes.map((cls) {
              final classData = List<Map<String, dynamic>>.from(heatmap[cls] ?? []);
              final classTotal = classData.fold<int>(0, (sum, h) => sum + (h['count'] as int));
              final color = _classColors[cls] ?? Colors.grey;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text(cls, style: const TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text('$classTotal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet showing alerts for a specific hour.
class _AlertsForHourSheet extends StatefulWidget {
  final String cameraId;
  final String cameraAlias;
  final int hour;
  final String? selectedClass;
  final String backendUrl;
  final String sessionToken;

  const _AlertsForHourSheet({
    required this.cameraId,
    required this.cameraAlias,
    required this.hour,
    this.selectedClass,
    required this.backendUrl,
    required this.sessionToken,
  });

  @override
  State<_AlertsForHourSheet> createState() => _AlertsForHourSheetState();
}

class _AlertsForHourSheetState extends State<_AlertsForHourSheet> {
  List<dynamic> _alerts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    try {
      final url = '${widget.backendUrl}/api/cameras/${widget.cameraId}/heatmap/alerts?hour=${widget.hour}';
      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.sessionToken}'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _alerts = data['alerts'] ?? [];
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '${widget.cameraAlias} · ${widget.hour}:00-${widget.hour + 1}:00',
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text('${_alerts.length} alerts', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _alerts.isEmpty
                        ? const Center(child: Text('No alerts for this hour'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _alerts.length,
                            itemBuilder: (context, index) {
                              final alert = _alerts[index];
                              final className = alert['class_name'] ?? 'unknown';
                              final confidence = alert['confidence'] ?? 0;
                              final seenAt = alert['seen_at'] ?? '';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getClassColor(className),
                                  child: Text(className[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                                title: Text('${className.toString().toUpperCase()} · ${(confidence * 100).toInt()}%'),
                                subtitle: Text(seenAt.length > 19 ? seenAt.substring(11, 19) : seenAt),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getClassColor(String cls) {
    const colors = {
      'person': Colors.blue,
      'car': Colors.orange,
      'cat': Colors.purple,
      'dog': Colors.green,
    };
    return colors[cls] ?? Colors.grey;
  }
}
