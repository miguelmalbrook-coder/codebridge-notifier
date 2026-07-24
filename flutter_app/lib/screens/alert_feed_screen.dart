import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _scrollCtrl.addListener(_onScroll);
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
      final parsed = data.map((json) => Alert.fromJson(json as Map<String, dynamic>)).toList();

      setState(() {
        _alerts.addAll(parsed);
        _hasMore = parsed.length == 20;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load alerts: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadAlerts();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alert History')),
      body: _alerts.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _alerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('No alerts yet', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('When something is detected, it will show here.', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: _alerts.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _alerts.length) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ));
                    }
                    return AlertTile(alert: _alerts[index]);
                  },
                ),
    );
  }
}
