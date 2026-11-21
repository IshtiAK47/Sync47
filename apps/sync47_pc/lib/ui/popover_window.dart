import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/clip_item.dart';
import '../services/app_state.dart';
import 'qr_pairing_dialog.dart';
import 'settings_dialog.dart';

class PopoverWindow extends StatelessWidget {
  final AppState appState;
  final VoidCallback? onPairRequested;

  const PopoverWindow({
    super.key,
    required this.appState,
    this.onPairRequested,
  });

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
          body: SafeArea(
            child: Column(
              children: [
                // 1. Top Status Header with Master Auto-Sync Toggle
                _buildHeader(context),
                const Divider(height: 1, thickness: 1),

                // 2. Read-only Recent Synced Clips Feed
                Expanded(
                  child: appState.history.isEmpty
                      ? _buildEmptyState(context)
                      : _buildHistoryList(context),
                ),

                const Divider(height: 1, thickness: 1),

                // 3. Quick Action Bar (Pair Phone & Settings)
                _buildBottomBar(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final status = appState.connectionStatus;

    Color badgeBg;
    Color badgeText;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case ConnectionStatus.connected:
        badgeBg = const Color(0xFF10B981).withValues(alpha: 0.15);
        badgeText = const Color(0xFF059669);
        statusLabel = appState.connectedDeviceName ?? 'Connected';
        statusIcon = Icons.wifi_rounded;
        break;
      case ConnectionStatus.waiting:
        badgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
        badgeText = const Color(0xFFD97706);
        statusLabel = '${appState.localIp}:${appState.port}';
        statusIcon = Icons.wifi_find_rounded;
        break;
      case ConnectionStatus.paused:
        badgeBg = Colors.grey.withValues(alpha: 0.15);
        badgeText = Colors.grey.shade600;
        statusLabel = 'Sync Paused';
        statusIcon = Icons.pause_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // App Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Sync47',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Live Pill Badge
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 12, color: badgeText),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      statusLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: badgeText,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Master Auto-Sync Toggle Switch
          Tooltip(
            message: appState.isPaused ? 'Resume Auto-Sync' : 'Pause Auto-Sync',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appState.isPaused ? 'OFF' : 'ON',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: appState.isPaused ? Colors.grey : const Color(0xFF10B981),
                  ),
                ),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: !appState.isPaused,
                    activeThumbColor: const Color(0xFF10B981),
                    onChanged: (_) => appState.togglePause(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sync_alt_rounded,
                size: 32,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Zero-Tap Clipboard Sync Ready',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Copy text anywhere on PC (Ctrl+C) or Phone to automatically sync over your local Wi-Fi. No manual sending needed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: appState.history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final clip = appState.history[index];
        return _buildClipCard(context, clip);
      },
    );
  }

  Widget _buildClipCard(BuildContext context, ClipItem clip) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPhone = clip.source == 'phone';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        appState.copyClip(clip);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Re-copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Source badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPhone
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFF4F46E5).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPhone ? Icons.phone_android_rounded : Icons.laptop_mac_rounded,
                        size: 10,
                        color: isPhone ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isPhone ? 'Phone' : 'PC',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isPhone ? const Color(0xFF059669) : const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatRelativeTime(clip.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Tap to re-copy',
                  style: TextStyle(fontSize: 9, color: Colors.grey),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => appState.deleteClip(clip),
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: Icon(Icons.close_rounded, size: 14, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),

            // Read-only 2-line preview
            Text(
              clip.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Pair Phone button
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.qr_code_rounded, size: 15),
              label: const Text('Pair Phone (QR Code)', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => QrPairingDialog(appState: appState),
                );
              },
            ),
          ),
          const SizedBox(width: 8),

          // Settings button
          IconButton.outlined(
            icon: const Icon(Icons.settings_outlined, size: 16),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            tooltip: 'Settings',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => SettingsDialog(appState: appState),
              );
            },
          ),
        ],
      ),
    );
  }
}
