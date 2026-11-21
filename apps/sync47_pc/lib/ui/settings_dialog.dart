import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import '../services/app_state.dart';

class SettingsDialog extends StatefulWidget {
  final AppState appState;

  const SettingsDialog({super.key, required this.appState});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.appState;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_outlined, color: Color(0xFF4F46E5), size: 24),
                const SizedBox(width: 10),
                Text(
                  'Sync47 Settings',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Launch at Windows Startup', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Run silently in tray on PC boot', style: TextStyle(fontSize: 12)),
              value: app.launchAtStartup,
              activeTrackColor: const Color(0xFF4F46E5),
              onChanged: (val) async {
                await app.setLaunchAtStartup(val);
                if (val) {
                  await launchAtStartup.enable();
                } else {
                  await launchAtStartup.disable();
                }
                setState(() {});
              },
            ),
            const Divider(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start Minimized to Tray', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Do not show window on launch', style: TextStyle(fontSize: 12)),
              value: app.startMinimized,
              activeTrackColor: const Color(0xFF4F46E5),
              onChanged: (val) async {
                await app.setStartMinimized(val);
                setState(() {});
              },
            ),
            const Divider(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ignore Password Managers', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Exclude Bitwarden, 1Password, KeePass', style: TextStyle(fontSize: 12)),
              value: app.ignorePasswordManagers,
              activeTrackColor: const Color(0xFF4F46E5),
              onChanged: (val) async {
                await app.setIgnorePasswordManagers(val);
                setState(() {});
              },
            ),
            const Divider(height: 12),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.redAccent),
                    label: const Text('Clear History', style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await app.clearHistory();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.phonelink_erase, size: 16, color: Colors.orangeAccent),
                    label: const Text('Unpair Phone', style: TextStyle(color: Colors.orangeAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orangeAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await app.unpairDevice();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
