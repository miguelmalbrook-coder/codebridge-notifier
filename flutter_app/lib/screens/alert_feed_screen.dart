import 'dart:async';

import 'package:flutter/material.dart';
import 'package:realtime_client/realtime_client.dart';
import '../supabase/client.dart';
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

  // Filters
  String? _filterCamera;
  String? _filterClass;
  List<String> _cameraOptions = [];
  List<String> _classOptions = ['person', 'car', 'cat', 'dog', 'motorcycle', 'truck', 'bus', 'bicycle'];

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _scrollCtrl.addListener(_onScroll);
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('alerts-feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'alerts',
          callback: (payload) {
            final newAlert = Alert.fromJson(
                payload.newRecord as Map<String, dynamic>);
            if (mounted) {
              setState(() {
                _allAlerts.insert(0, newAlert);
                // Extract camera options dynamically
                if (!_cameraOptions.contains(newAlert.cameraId)) {
                  _cameraOptions.add(newAlert.cameraId);
                }
              });
            }
          },
        )
        .subscribe();
  }

  List<Alert> get _filteredAlerts {
    return _allAlerts.where((a) {
      if (_filterCamera != null && a.cameraId != _filterCamera) return false;
      if (_filterClass != null && a.className != _filterClass) return false;
      return true;
    }).toList();
  }

  Future<void> _loadAlerts() async {
    if (!_hasMore) return;
    setState(() => _loading = _page == 1);

    try {
      final response = await supabase
          .from('alerts')
          .select('*')
          .order('seen_at', ascending: false)
          .range((_page - 1) * 20, _page * 20 - 1);

      final data = response as List<dynamic>;
      final parsed =
          data.map((json) => Alert.fromJson(json as Map<String, dynamic>)).toList();

      // Extract camera options
      final cameras = parsed.map((a) => a.cameraId).toSet();
      for (final c in cameras) {
        if (!_cameraOptions.contains(c)) _cameraOptions.add(c);
      }

      setState(() {
        _allAlerts.addAll(parsed);
        _hasMore = parsed.length == 20;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load alerts: $e'),
              backgroundColor: Colors.red),
        );
      }
      setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadAlerts();
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredAlerts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _page = 1;
                _hasMore = true;
                _allAlerts = [];
              });
              _loadAlerts();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter bar ──
          if (_cameraOptions.isNotEmpty || _allAlerts.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Camera filter chips
                  if (_cameraOptions.isNotEmpty) ...[
                    Text('Camera', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip('All', _filterCamera == null, () {
                            setState(() => _filterCamera = null);
                          }),
                          ..._cameraOptions.map((cam) => _filterChip(
                                cam,
                                _filterCamera == cam,
                                () => setState(() => _filterCamera = cam),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Class filter chips
                  Text('Class', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', _filterClass == null, () {
                          setState(() => _filterClass = null);
                        }),
                        ..._classOptions.map((cls) => _filterChip(
                              cls,
                              _filterClass == cls,
                              () => setState(() => _filterClass = cls),
                            )),
                      ],
                    ),
                  ),
                  // Active filter indicator
                  if (_filterCamera != null || _filterClass != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${filtered.length} of ${_allAlerts.length} alerts',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setState(() {
                            _filterCamera = null;
                            _filterClass = null;
                          }),
                          child: Text(
                            'Clear filters',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          if (_cameraOptions.isNotEmpty || _allAlerts.isNotEmpty)
            const Divider(height: 1),

          // ── Alert list ──
          Expanded(
            child: _allAlerts.isEmpty && _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty && !_loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_list_off,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              _allAlerts.isEmpty
                                  ? 'All clear'
                                  : 'No alerts match filters',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _allAlerts.isEmpty
                                  ? 'When something is detected, alerts appear here instantly.'
                                  : 'Try changing your filter selection.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          setState(() {
                            _page = 1;
                            _hasMore = true;
                            _allAlerts = [];
                          });
                          await _loadAlerts();
                        },
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == filtered.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return AlertTile(alert: filtered[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
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
