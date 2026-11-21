import 'package:flutter/material.dart';
import '../providers/android_app_state.dart';
import 'qr_scanner_screen.dart';

class OnboardingScreen extends StatelessWidget {
  final AndroidAppState appState;

  const OnboardingScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              // Hero Icon
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sync_alt_rounded,
                  size: 46,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),

              // Title
              Text(
                'Welcome to Sync47',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Instant, local Wi-Fi clipboard synchronization between your Android device and PC.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),

              // Feature Highlights
              _buildFeatureRow(
                Icons.wifi_lock_rounded,
                '100% Offline & Encrypted',
                'AES-256-GCM local Wi-Fi sync. No cloud, no servers, no accounts.',
                theme,
              ),
              const SizedBox(height: 16),
              _buildFeatureRow(
                Icons.battery_charging_full_rounded,
                'Ultra-Low Battery (<15 MB RAM)',
                'Dedicated background process goes completely dormant when Wi-Fi drops.',
                theme,
              ),
              const SizedBox(height: 16),
              _buildFeatureRow(
                Icons.touch_app_rounded,
                'Zero-Friction Quick Tile & Share',
                'Push clips to PC in 1 tap directly from the notification shade or share menu.',
                theme,
              ),

              const Spacer(),

              // Primary CTA
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan PC QR Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => QrScannerScreen(appState: appState),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.lan_rounded, size: 16),
                  label: const Text('Enter PC IP Manually', style: TextStyle(fontSize: 14)),
                  onPressed: () => _showManualIpDialog(context, appState),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualIpDialog(BuildContext context, AndroidAppState app) {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '47471');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Manual PC Connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the IP address and port shown in Sync47 on your PC:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'PC IPv4 Address',
                  hintText: '192.168.1.5',
                  prefixIcon: Icon(Icons.lan_rounded),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '47471',
                  prefixIcon: Icon(Icons.numbers_rounded),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final ip = ipController.text.trim();
                final port = int.tryParse(portController.text.trim()) ?? 47471;
                if (ip.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  await app.manualPair(ip: ip, port: port);
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
