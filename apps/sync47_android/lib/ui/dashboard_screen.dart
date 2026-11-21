import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/clip_record.dart';
import '../providers/android_app_state.dart';
import 'qr_scanner_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  final AndroidAppState appState;

  const DashboardScreen({super.key, required this.appState});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  bool _showAdbInstructions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.appState.checkPermissions();
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(time);
  }

  void _showManualIpDialog(BuildContext context, AndroidAppState app) {
    final ipController = TextEditingController(text: app.pcIp);
    final portController = TextEditingController(text: app.pcPort.toString());

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Configure PC IP & Port', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the local Wi-Fi IP address shown on your PC in Sync47:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'PC IPv4 Address',
                  hintText: 'e.g. 192.168.1.5',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.appState;

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Sync47', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                tooltip: 'Scan PC QR Code',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => QrScannerScreen(appState: app),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(appState: app),
                    ),
                  );
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await app.init();
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Connection & Live Diagnostics Card
                _buildConnectionCard(context, app),
                const SizedBox(height: 16),

                // 2. Setup Checklist Card for True Zero-Tap Background Sync
                _buildSetupChecklistCard(context, app),
                const SizedBox(height: 20),

                // 3. History Feed Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Synced Clips (${app.history.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (app.history.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: const Text('Clear All', style: TextStyle(fontSize: 12)),
                        onPressed: () => app.clearHistory(),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // 4. Clips List
                if (app.history.isEmpty)
                  _buildEmptyHistory(context)
                else
                  ...app.history.map((clip) => _buildClipCard(context, clip)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard(BuildContext context, AndroidAppState app) {
    final status = app.status.toLowerCase();
    final isConnected = status.startsWith('connected');
    final isPaused = app.isPaused;

    Color statusColor;
    IconData statusIcon;

    if (isPaused) {
      statusColor = Colors.grey;
      statusIcon = Icons.pause_circle_filled_rounded;
    } else if (isConnected) {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle_rounded;
    } else if (status.contains('reconnecting') || status.contains('connecting')) {
      statusColor = const Color(0xFF3B82F6);
      statusIcon = Icons.sync_rounded;
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusIcon = Icons.wifi_off_rounded;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.pcName.isNotEmpty ? app.pcName : 'PC Workstation',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.pcIp.isNotEmpty ? '${app.pcIp}:${app.pcPort}' : 'No IP configured',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  tooltip: isPaused ? 'Resume Sync' : 'Pause Sync',
                  onPressed: () => app.togglePause(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isPaused ? 'Sync is currently paused' : app.status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Diagnostic Result Banner (if test was run)
            if (app.testConnectionResult != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: (app.testConnectionSuccess == true)
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (app.testConnectionSuccess == true)
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      (app.testConnectionSuccess == true)
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 16,
                      color: (app.testConnectionSuccess == true)
                          ? const Color(0xFF10B981)
                          : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        app.testConnectionResult!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: (app.testConnectionSuccess == true)
                              ? const Color(0xFF047857)
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: app.isTestingConnection
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check_rounded, size: 16),
                    label: Text(
                      app.isTestingConnection ? 'Testing...' : 'Test Connection',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: app.isTestingConnection ? null : () => app.testConnection(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Manual IP', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showManualIpDialog(context, app),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupChecklistCard(BuildContext context, AndroidAppState app) {
    final hasAccessibility = app.accessibilityEnabled;
    final hasOverlay = app.overlayGranted;
    final hasReadLogs = app.readLogsGranted;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_rounded, size: 20, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                const Text(
                  'Zero-Tap Auto-Sync Checklist',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: 'Re-check Permissions',
                  onPressed: () => app.checkPermissions(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Android 10+ restricts background clipboard reads. Enable the items below for invisible two-way background sync.',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
            ),
            const Divider(height: 20),

            // Item 1: Accessibility Service
            _buildChecklistItem(
              title: 'Accessibility Auto-Sync',
              subtitle: 'Detects copy actions instantly in the background without opening the app.',
              isEnabled: hasAccessibility,
              actionLabel: hasAccessibility ? 'Active' : 'Enable',
              onAction: hasAccessibility ? null : () => app.openAccessibilitySettings(),
            ),
            const SizedBox(height: 12),

            // Item 2: Display Over Other Apps (Overlay)
            _buildChecklistItem(
              title: 'Display Over Other Apps',
              subtitle: 'Allows the invisible 1×1 pixel focus overlay required to read clipboard without flicker.',
              isEnabled: hasOverlay,
              actionLabel: hasOverlay ? 'Granted' : 'Grant',
              onAction: hasOverlay ? null : () => app.openOverlaySettings(),
            ),
            const SizedBox(height: 12),

            // Item 3: ADB Logcat Watcher (Power Users)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasReadLogs ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: hasReadLogs ? const Color(0xFF10B981) : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'ADB Log-Watcher',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: hasReadLogs
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              hasReadLogs ? 'Granted' : 'Optional',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: hasReadLogs ? const Color(0xFF059669) : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Power-user alternative: watches system copy denials via ADB logcat.',
                        style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.25),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => setState(() => _showAdbInstructions = !_showAdbInstructions),
                        child: Text(
                          _showAdbInstructions ? 'Hide ADB command ▲' : 'Show 1-time ADB command ▼',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF4F46E5), fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_showAdbInstructions) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: SelectableText(
                                  'adb shell pm grant com.sync47.app android.permission.READ_LOGS',
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 10),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                tooltip: 'Copy command',
                                onPressed: () {
                                  Clipboard.setData(
                                    const ClipboardData(
                                      text: 'adb shell pm grant com.sync47.app android.permission.READ_LOGS',
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Command copied to clipboard'), duration: Duration(seconds: 1)),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Item 4: Quick Settings Tile & Battery
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_to_photos_rounded, size: 14),
                    label: const Text('Add QS Tile', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => app.requestAddTile(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.battery_saver_rounded, size: 14),
                    label: const Text('Battery Settings', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => app.openBatterySettings(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistItem({
    required String title,
    required String subtitle,
    required bool isEnabled,
    required String actionLabel,
    required VoidCallback? onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isEnabled ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 18,
          color: isEnabled ? const Color(0xFF10B981) : Colors.grey,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.25)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (onAction != null)
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: onAction,
            child: Text(actionLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF059669),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyHistory(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.content_paste_rounded, size: 44, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          const Text('No clips synced yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          const Text(
            'Copy any text or link on your PC to see it appear here.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildClipCard(BuildContext context, ClipRecord clip) {
    final isPhone = clip.source == 'phone';
    final isUrl = clip.text.trim().startsWith('http://') || clip.text.trim().startsWith('https://');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPhone
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFF4F46E5).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPhone ? 'Phone' : 'PC',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isPhone ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(clip.timestamp),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Spacer(),
                if (isUrl) ...[
                  IconButton(
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Open Link',
                    onPressed: () async {
                      final uri = Uri.tryParse(clip.text.trim());
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                ],
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Copy',
                  onPressed: () {
                    widget.appState.copyClip(clip);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Delete',
                  onPressed: () => widget.appState.deleteClip(clip.id),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              clip.text,
              maxLines: 4,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
