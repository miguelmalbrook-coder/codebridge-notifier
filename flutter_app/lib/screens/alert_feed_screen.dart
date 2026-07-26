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
  List<Alert> _alerts = [];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = true;
  final _scrollCtrl = ScrollController();
  var _channel;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _scrollCtrl.addListener(_onScroll);
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    // Listen for new alerts via Supabase Realtime
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
                _alerts.insert(0, newAlert);
              });
            }
          },
        )
        .subscribe();
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

      setState(() {
        _alerts.addAll(parsed);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _page = 1;
                _hasMore = true;
                _alerts = [];
              });
              _loadAlerts();
            },
          ),
        ],
      ),
      body: _alerts.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _alerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('All clear',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        'When something is detected, alerts appear here instantly.',
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
                      _alerts = [];
                    });
                    await _loadAlerts();
                  },
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _alerts.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _alerts.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return AlertTile(alert: _alerts[index]);
                    },
                  ),
                ),
    );
  }
}
