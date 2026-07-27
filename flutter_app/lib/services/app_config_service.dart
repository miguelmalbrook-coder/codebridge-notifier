import 'package:flutter/material.dart';
import '../config.dart';
import '../supabase/client.dart';

/// Reads app config (tunnel URL + subscription) from Supabase.
/// Falls back to hardcoded config if Supabase table doesn't exist yet.
class AppConfigService {
  static final AppConfigService _instance = AppConfigService._();
  factory AppConfigService() => _instance;
  AppConfigService._();

  String? _ntfyUrl;  // Separate ntfy tunnel URL
  bool? _subscribed;
  bool _loaded = false;

  bool get subscribed => _subscribed ?? true;
  bool get loaded => _loaded;
  String get ntfyUrl => _ntfyUrl ?? BackendConfig.baseUrl.replaceAll(':8001', ':8090');

  Future<void> load() async {
    if (_loaded) return;
    try {
      final response = await supabase
          .from('app_config')
          .select('tunnel_url, ntfy_tunnel_url, subscribed')
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (response != null) {
        final tunnelUrl = response['tunnel_url'] as String?;
        // Set the tunnel URL on BackendConfig so all code picks it up
        BackendConfig.tunnelUrl = (tunnelUrl?.isNotEmpty ?? false) ? tunnelUrl : null;

        final ntfyTunnelUrl = response['ntfy_tunnel_url'] as String?;
        _ntfyUrl = (ntfyTunnelUrl?.isNotEmpty ?? false) ? ntfyTunnelUrl : null;

        _subscribed = response['subscribed'] as bool? ?? true;
      }
    } catch (e) {
      debugPrint('AppConfigService: failed to load from Supabase: $e');
    }
    _loaded = true;
  }
}

/// Subscription gate — wraps the app and shows a "pay bill" screen if unsubscribed.
class SubscriptionGate extends StatefulWidget {
  final Widget child;

  const SubscriptionGate({super.key, required this.child});

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  final _config = AppConfigService();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _config.load();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_config.subscribed) {
      return const _PayWall();
    }

    return widget.child;
  }
}

class _PayWall extends StatelessWidget {
  const _PayWall();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 80, color: theme.colorScheme.error),
              const SizedBox(height: 24),
              Text(
                'Subscription Expired',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Please contact Codebridge admin to pay your bills and restore access.',
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Icon(Icons.phone, size: 24, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                'Codebridge Consultancy',
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
