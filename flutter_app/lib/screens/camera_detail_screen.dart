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
  bool _arModelLoading = false;
  double _arModelProgress = 0.0;
  String _arSelectedModel = 'yolo11n.pt';
  Set<String> _arTargets = {'person', 'car', 'cat', 'dog'};

  static const _allClasses = [
    // People & Vehicles
    'person', 'car', 'truck', 'bus', 'motorcycle', 'bicycle',
    // Animals
    'cat', 'dog', 'bird', 'horse', 'sheep', 'cow', 'bear', 'elephant',
    // Nature & Outdoor
    'potted plant', 'bench', 'umbrella',
    // Objects
    'handbag', 'suitcase', 'bottle', 'cup', 'laptop', 'cell phone',
    'tv', 'book', 'clock', 'scissors',
  ];

  static const _arModels = [
    {'name': 'yolo11n.pt', 'label': 'Nano (Fast)', 'desc': 'Fastest, least accurate'},
    {'name': 'yolo11s.pt', 'label': 'Small', 'desc': 'Good balance'},
    {'name': 'yolo11m.pt', 'label': 'Medium', 'desc': 'Better accuracy'},
    {'name': 'yolo11l.pt', 'label': 'Large', 'desc': 'High accuracy'},
    {'name': 'yolo11x.pt', 'label': 'XLarge', 'desc': 'Best accuracy, slowest'},
  ];

  static const _classColors = {
    'person': Colors.blue,
    'car': Colors.orange,
    'cat': Colors.purple,
    'dog': Colors.green,
    'truck': Colors.red,
    'bus': Colors.teal,
    'motorcycle': Colors.pink,
    'bicycle': Colors.indigo,
    'bird': Colors.lightBlue,
    'horse': Colors.brown,
    'sheep': Colors.grey,
    'cow': Colors.amber,
    'bear': Colors.deepOrange,
    'elephant': Colors.blueGrey,
    'potted plant': Colors.green,
    'bench': Colors.brown,
    'umbrella': Colors.cyan,
    'handbag': Colors.pink,
    'suitcase': Colors.indigo,
    'bottle': Colors.teal,
    'cup': Colors.orange,
    'laptop': Colors.grey,
    'cell phone': Colors.blue,
    'tv': Colors.black,
    'book': Colors.red,
    'clock': Colors.amber,
    'scissors': Colors.blueGrey,
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

  bool _arBusy = false; // Guard against concurrent requests

  void _startArSession() {
    _arOverlay = true;
    _arLoading = true;
    _arModelLoading = true;
    _arModelProgress = 0.0;
    _arFrame = null;
    _arDetections = [];
    _arBusy = false;
    setState(() {});
    // Start polling — first frame will show loading, then model loads
    _pollArFrame();
    _arPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollArFrame());
  }

  void _stopArSession() {
    _arOverlay = false;
    _arPollTimer?.cancel();
    _arPollTimer = null;
    _arFrame = null;
    _arDetections = [];
    _arBusy = false;
    setState(() {});
  }

  Future<void> _pollArFrame() async {
    if (!_arOverlay || !mounted || _arBusy) return;
    _arBusy = true;
    try {
      final url = '$_backendUrl/api/cameras/${widget.cameraId}/detect?model=$_arSelectedModel';
      final resp = await http.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200 && mounted) {
        // Parse detections from header
        final detHeader = resp.headers['x-detections'];
        List<Map<String, dynamic>> dets = [];
        if (detHeader != null) {
          final decoded = jsonDecode(detHeader) as List;
          dets = decoded.cast<Map<String, dynamic>>();
        }
        // Filter by selected classes (client-side)
        final filtered = dets.where((d) => _arTargets.contains(d['class'])).toList();
        setState(() {
          _arFrame = resp.bodyBytes;
          _arDetections = filtered;
          _arLoading = false;
          _arModelLoading = false;
          _arModelProgress = 1.0;
        });
      } else if (mounted && resp.statusCode == 404) {
        // No frame yet — keep loading
        setState(() => _arLoading = true);
      } else if (mounted && resp.statusCode == 503) {
        // Model loading — show progress
        final body = jsonDecode(resp.body);
        setState(() {
          _arModelLoading = true;
          _arModelProgress = (body['progress'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (e) {
      debugPrint('AR poll error: $e');
    } finally {
      _arBusy = false;
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_arModelLoading) ...[
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: _arModelProgress > 0 ? _arModelProgress : null,
                  backgroundColor: Colors.amber.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.amber),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _arModelProgress > 0
                    ? 'Loading YOLO model... ${(_arModelProgress * 100).toInt()}%'
                    : 'Loading YOLO model...',
                style: const TextStyle(color: Colors.amber),
              ),
              const SizedBox(height: 4),
              Text(
                _arModels.firstWhere((m) => m['name'] == _arSelectedModel)['label']!,
                style: TextStyle(color: Colors.amber.withOpacity(0.6), fontSize: 12),
              ),
            ] else ...[
              const CircularProgressIndicator(color: Colors.amber),
              const SizedBox(height: 12),
              const Text('Starting AR detection...', style: TextStyle(color: Colors.amber)),
            ],
          ],
        ),
      );
    }

    if (_arFrame != null) {
      return Image.memory(
        _arFrame!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
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
          // Model selector
          Row(
            children: [
              Icon(Icons.speed, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('Model:', style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _arSelectedModel,
                  isDense: true,
                  underline: const SizedBox(),
                  style: theme.textTheme.bodySmall,
                  items: _arModels.map((m) => DropdownMenuItem(
                    value: m['name'],
                    child: Text('${m['label']}', style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _arSelectedModel = v);
                      // Restart AR with new model
                      _stopArSession();
                      _startArSession();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Model loading progress
          if (_arModelLoading && _arModelProgress > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                value: _arModelProgress,
                backgroundColor: Colors.amber.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation(Colors.amber),
                minHeight: 3,
              ),
            ),
          // Detection classes
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
                  fontSize: 11,
                  color: isActive ? Colors.white : color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                )),
                selected: isActive,
                onSelected: (_) => _toggleArClass(cls),
                selectedColor: color,
                checkmarkColor: Colors.white,
                avatar: isActive
                    ? null
                    : Icon(_iconForClass(cls), size: 14, color: color),
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
      case 'cat': case 'dog': case 'bird': case 'horse': case 'sheep':
      case 'cow': case 'bear': case 'elephant': return Icons.pets;
      case 'truck': return Icons.local_shipping;
      case 'bus': return Icons.directions_bus;
      case 'motorcycle': return Icons.two_wheeler;
      case 'bicycle': return Icons.pedal_bike;
      case 'potted plant': return Icons.grass;
      case 'bench': return Icons.chair;
      case 'umbrella': return Icons.umbrella;
      case 'handbag': case 'suitcase': return Icons.work;
      case 'bottle': case 'cup': return Icons.local_drink;
      case 'laptop': return Icons.laptop;
      case 'cell phone': return Icons.phone;
      case 'tv': return Icons.tv;
      case 'book': return Icons.book;
      case 'clock': return Icons.access_time;
      case 'scissors': return Icons.content_cut;
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
                const Icon(Icons.insights, size: 20),
                const SizedBox(width: 8),
                Text('Activity (24h)', style: theme.textTheme.titleMedium),
              ]),
              const SizedBox(height: 20),
              Icon(Icons.hourglass_empty, size: 40, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text('No detections yet', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('Detections will appear here once YOLO starts finding objects.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6))),
            ],
          ),
        ),
      );
    }

    // Calculate per-class totals and max
    int maxCount = 0;
    final Map<String, int> classTotals = {};
    for (final cls in classes) {
      final classData = List<Map<String, dynamic>>.from(heatmap[cls] ?? []);
      final clsTotal = classData.fold<int>(0, (sum, h) => sum + (h['count'] as int));
      classTotals[cls] = clsTotal;
      for (final h in classData) {
        final count = h['count'] as int;
        if (count > maxCount) maxCount = count;
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            ),
            child: Row(
              children: [
                Icon(Icons.insights, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Activity (24h)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$total', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // ── Stacked bar chart ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            child: SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (hour) {
                  // Build stacked segments per class
                  int hourTotal = 0;
                  final segments = <MapEntry<String, int>>[];
                  for (final cls in classes) {
                    final classData = List<Map<String, dynamic>>.from(heatmap[cls] ?? []);
                    final count = hour < classData.length ? classData[hour]['count'] as int : 0;
                    if (count > 0) segments.add(MapEntry(cls, count));
                    hourTotal += count;
                  }
                  final barHeight = maxCount > 0 ? (hourTotal / maxCount) * 110 : 0.0;
                  final isNow = hour == DateTime.now().hour;

                  return Expanded(
                    child: GestureDetector(
                      onTap: hourTotal > 0 ? () => _showAlertsForHour(hour, null) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Count label
                            if (hourTotal > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  '$hourTotal',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: isNow ? Colors.amber.shade700 : theme.colorScheme.onSurfaceVariant,
                                    fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            // Stacked bar
                            Container(
                              height: barHeight.clamp(hourTotal > 0 ? 6 : 0, 110),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                border: isNow ? Border.all(color: Colors.amber, width: 1.5) : null,
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Column(
                                children: segments.map((seg) {
                                  final segHeight = maxCount > 0
                                      ? (seg.value / maxCount) * 110
                                      : 0.0;
                                  final color = _classColors[seg.key] ?? Colors.grey;
                                  return Expanded(
                                    flex: (seg.value * 100).clamp(1, 1000),
                                    child: Container(
                                      color: color.withOpacity(isNow ? 1.0 : 0.75),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            // Hour label
                            if (hour % 3 == 0 || hour == DateTime.now().hour)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  '${hour}h',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                                    color: isNow ? Colors.amber.shade700 : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // ── Legend ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: classes.map((cls) {
                final color = _classColors[cls] ?? Colors.grey;
                final count = classTotals[cls] ?? 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 4),
                    Text(cls, style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 2),
                    Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                  ],
                );
              }).toList(),
            ),
          ),

          // ── Per-class breakdown ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('By Class', style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ),
          ...classes.map((cls) {
            final classData = List<Map<String, dynamic>>.from(heatmap[cls] ?? []);
            final classTotal = classData.fold<int>(0, (sum, h) => sum + (h['count'] as int));
            final color = _classColors[cls] ?? Colors.grey;
            final pct = total > 0 ? classTotal / total : 0.0;
            // Peak hour
            int peakHour = 0;
            int peakCount = 0;
            for (int i = 0; i < classData.length; i++) {
              final c = classData[i]['count'] as int;
              if (c > peakCount) { peakCount = c; peakHour = i; }
            }
            return InkWell(
              onTap: classTotal > 0 ? () => _showAlertsForHour(peakHour, cls) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text(cls, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: color.withOpacity(0.12),
                          valueColor: AlwaysStoppedAnimation(color.withOpacity(0.7)),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      child: Text('$classTotal', textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                    ),
                    if (peakCount > 0) ...[
                      const SizedBox(width: 4),
                      Text('${peakHour}h', style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
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
                              String timeStr = '';
                              if (seenAt is String && seenAt.length > 19) {
                                try {
                                  final dt = DateTime.parse(seenAt);
                                  final local = dt.isUtc ? dt.toLocal() : dt;
                                  timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                                } catch (_) {
                                  timeStr = seenAt.substring(11, 19);
                                }
                              }

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getClassColor(className),
                                  child: Text(className[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                                title: Text('${className.toString().toUpperCase()} · ${(confidence * 100).toInt()}%'),
                                subtitle: Text(timeStr),
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
