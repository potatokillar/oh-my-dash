import 'package:flutter/material.dart';

import '../app_state.dart';
import 'project_list_page.dart';
import 'session_list_page.dart';

/// Per-device home: 项目 / 会话 two tabs. Each tab keeps its own Scaffold
/// (own AppBar/FAB); the back arrow pops the whole page to the device list.
class DeviceHomePage extends StatefulWidget {
  final AppState state;
  const DeviceHomePage({super.key, required this.state});

  @override
  State<DeviceHomePage> createState() => _DeviceHomePageState();
}

class _DeviceHomePageState extends State<DeviceHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          ProjectListPage(state: widget.state),
          SessionListPage(state: widget.state),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '项目'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: '会话'),
        ],
      ),
    );
  }
}
