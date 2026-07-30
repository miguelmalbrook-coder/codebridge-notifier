import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/client.dart';
import '../utils/error_utils.dart';
import '../models/alert.dart';
import '../widgets/alert_tile.dart';

class AlertFeedScreen extends StatefulWidget {
  const AlertFeedScreen({super.key});

  @override
  State<AlertFeedScreen> createState() => _AlertFeedScreenState();
}

class _AlertFeedScreenState extends State<AlertFeedScreen> {
  List<Alert> _allAlerts = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;
  final _scrollCtrl = ScrollController();
  dynamic _channel;
  Timer? _autoRefresh;

  // Filters — passed to server
  String? _filterCamera;
  String? _filterClass;
  List<String> _cameraOptions = [];
  static const _classOptions = ['person', 'car', 'cat', 'dog', 'motorcycle', 'truck', 'bus', 'bicycle'];

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _scrollCtrl.addListener(_onScroll);
    _subscribeRealtime();
    _autoRefresh = Timer.periodic(const Duration(seconds: 5), (_) => _silentRefresh());
  }

  void _silentRefresh() {
    _fetchAlerts(page: 1, replace: true);
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('alerts-feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'alerts',
          callback: (payload) {
            final newAlert = Alert.fromJson(payload.newRecord as Map<String, dynamic>);
            if (mounted) {
              setState(() {
                _allAlerts.insert(0, newAlert);
                if (!_cameraOptions.contains(newAlert.cameraId)) {
                  _cameraOptions.add(newAlert.cameraId);
                }
              });
            }
          },
        )
        .subscribe();
  }

  /// Server-side filtered query
  Future<void> _fetchAlerts({required int page, bool replace = false}) async {
    try {
      var query = supabase.from('alerts').select('*');

      // Server-side filters
      if (_filterCamera != null) {
        query = query.eq('camera_id', _filterCamera!);
      }
      if (_filterClass != null) {
        query = query.eq('class_name', _filterClass!);
      }

      final start = (page - 1) * 50;
      final end = page * 50 - 1;

      final response = await query.order('seen_at', ascending: false).range(start, end);

      final data = response as List<dynamic>;
      final parsed = data.map((json) => Alert.fromJson(json as Map<String, dynamic>)).toList();

      // Get camera options from cameras table (not alerts — more reliable)
      if (page == 1 && _cameraOptions.isEmpty) {
        final camsData = await supabase.from('cameras').select('alias');
        final cams = (camsData as List).map((a) => a['alias'] as String).toSet();
        _cameraOptions = cams.toList()..sort();
      }

      if (mounted) {
        setState(() {
          if (replace) {
            _allAlerts = parsed;
          } else {
            // Deduplicate
            final existingIds = _allAlerts.map((a) => a.id).toSet();
            final newAlerts = parsed.where((a) => !existingIds.contains(a.id)).toList();
            _allAlerts.addAll(newAlerts);
          }
          _hasMore = parsed.length == 50;
          _page = page + 1;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _loadAlerts() {
    setState(() => _loading = true);
    _fetchAlerts(page: 1, replace: true);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      if (!_loading && _hasMore) {
        _fetchAlerts(page: _page);
      }
    }
  }

  void _applyFilter({String? camera, String? cls, bool clearCamera = false, bool clearClass = false}) {
    setState(() {
      _filterCamera = clearCamera ? null : (camera ?? _filterCamera);
      _filterClass = clearClass ? null : (cls ?? _filterClass);
      _allAlerts = [];
      _page = 1;
      _hasMore = true;
    });
    _loadAlerts();
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _channel?.unsubscribe();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Filter bar ──
        if (_cameraOptions.isNotEmpty || _allAlerts.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Camera', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', _filterCamera == null, () => _applyFilter(clearCamera: true)),
                      ..._cameraOptions.map((cam) => _filterChip(
                            cam, _filterCamera == cam, () => _applyFilter(camera: cam),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('Class', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', _filterClass == null, () => _applyFilter(clearClass: true)),
                      ..._classOptions.map((cls) => _filterChip(
                            cls, _filterClass == cls, () => _applyFilter(cls: cls),
                          )),
                    ],
                  ),
                ),
                if (_filterCamera != null || _filterClass != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${_allAlerts.length} alerts shown',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _applyFilter(clearCamera: true, clearClass: true),
                        child: Text('Clear filters',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (_cameraOptions.isNotEmpty || _allAlerts.isNotEmpty) const Divider(height: 1),

        // ── Alert list ──
        Expanded(
          child: _allAlerts.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _allAlerts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.filter_list_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(_filterCamera != null || _filterClass != null
                              ? 'No alerts match filters'
                              : 'All clear',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            _filterCamera != null || _filterClass != null
                                ? 'Try changing your filter selection.'
                                : 'When something is detected, alerts appear here instantly.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => _loadAlerts(),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _allAlerts.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _allAlerts.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return AlertTile(alert: _allAlerts[index]);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: theme.colorScheme.primaryContainer,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
