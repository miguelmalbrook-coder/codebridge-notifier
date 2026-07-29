import 'package:flutter/material.dart';
import 'camera_list_screen.dart';
import 'alert_feed_screen.dart';
import 'settings_screen.dart';
import '../services/fcm_service.dart';

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
  }

  @override
  void dispose() {
    FcmService().onNavigate = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_currentIndex])),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          CameraListScreen(),
          AlertFeedScreen(),
          SettingsScreen(),
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
  }
}
