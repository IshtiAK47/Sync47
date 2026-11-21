import 'package:flutter/material.dart';
import '../providers/android_app_state.dart';
import 'qr_scanner_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AndroidAppState appState;

  const SettingsScreen({super.key, required this.appState});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('SYNC SETTINGS', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-sync on Wi-Fi', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Connect automatically when Wi-Fi is active', style: TextStyle(fontSize: 12)),
            value: app.autoSyncWifi,
            activeTrackColor: const Color(0xFF4F46E5),
            onChanged: (val) async {
              await app.setAutoSyncWifi(val);
              setState(() {});
            },
          ),
          const Divider(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hands-Free Accessibility Auto-Send', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Optional: detect copy actions automatically (Power Users)', style: TextStyle(fontSize: 12)),
            value: app.autoSendAccessibility,
            activeTrackColor: const Color(0xFF4F46E5),
            onChanged: (val) async {
              await app.setAutoSendAccessibility(val);
              setState(() {});
            },
          ),
          const SizedBox(height: 24),

          Text('DEVICE PAIRING', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF4F46E5)),
            title: const Text('Scan Different PC QR Code', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QrScannerScreen(appState: app),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phonelink_erase_rounded, color: Colors.orangeAccent),
            title: const Text('Unpair Current PC', style: TextStyle(fontSize: 14, color: Colors.orangeAccent)),
            onTap: () async {
              final nav = Navigator.of(context);
              await app.unpair();
              nav.pop();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            title: const Text('Clear All Clip History', style: TextStyle(fontSize: 14, color: Colors.redAccent)),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await app.clearHistory();
              messenger.showSnackBar(
                const SnackBar(content: Text('History cleared')),
              );
            },
          ),

          const SizedBox(height: 24),
          Text('ABOUT', style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Sync47 is a 100% offline, peer-to-peer local Wi-Fi clipboard synchronization tool. All clips are encrypted end-to-end with AES-256-GCM. No data ever leaves your local network.',
            style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
