import 'package:flutter/material.dart';
import 'camera_list_screen.dart';
import 'alert_feed_screen.dart';
import 'settings_screen.dart';
import '../services/fcm_service.dart';
import '../services/monitoring_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const _titles = ['Cameras', 'Alerts', 'Settings'];
  static const _icons = [Icons.videocam_outlined, Icons.notifications_outlined, Icons.settings_outlined];
  static const _selectedIcons = [Icons.videocam, Icons.notifications, Icons.settings];

  @override
  void initState() {
    super.initState();
    // Wire up FCM notification tap → navigate to alerts tab
    FcmService().onNavigate = (tabIndex) {
      if (mounted) {
        setState(() => _currentIndex = tabIndex);
      }
    };
    // Start monitoring status polling
    MonitoringService().startPolling();
  }

  @override
  void dispose() {
    FcmService().onNavigate = null;
    MonitoringService().stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: MonitoringService().isActive,
      builder: (context, _) {
        final isMonitoring = MonitoringService().isMonitoring;
        return Scaffold(
          appBar: AppBar(title: Text(_titles[_currentIndex])),
          body: Column(
            children: [
              // ── Monitoring-off banner (shows on ALL tabs) ──
              if (!isMonitoring)
                MaterialBanner(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Icon(Icons.pause_circle_outline, color: theme.colorScheme.error),
                  content: Text(
                    'Monitoring is paused — no alerts will be sent',
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await MonitoringService().resume();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Monitoring resumed ✅'), backgroundColor: Colors.green),
                          );
                        }
                      },
                      child: const Text('RESUME'),
                    ),
                  ],
                ),
              // ── Tab content ──
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: const [
                    CameraListScreen(),
                    AlertFeedScreen(),
                    SettingsScreen(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: List.generate(3, (i) => NavigationDestination(
              icon: Icon(_icons[i]),
              selectedIcon: Icon(_selectedIcons[i]),
              label: _titles[i],
            )),
          ),
        );
      },
    );
  }
}
