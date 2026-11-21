import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/app_state.dart';

class QrPairingDialog extends StatefulWidget {
  final AppState appState;

  const QrPairingDialog({super.key, required this.appState});

  @override
  State<QrPairingDialog> createState() => _QrPairingDialogState();
}

class _QrPairingDialogState extends State<QrPairingDialog> {
  @override
  Widget build(BuildContext context) {
    final app = widget.appState;
    final payload = app.getPairingPayload();
    final qrData = payload.toJsonString();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF4F46E5), size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Pair with Sync47 Android',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Scan this QR code in the Sync47 Android app to establish encrypted local Wi-Fi sync.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 12),

              // Network Interface Selector if multiple interfaces exist
              if (app.availableInterfaces.length > 1) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.router_rounded, size: 16, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: app.localIp,
                            isDense: true,
                            isExpanded: true,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            items: app.availableInterfaces.map((iface) {
                              return DropdownMenuItem<String>(
                                value: iface.ip,
                                child: Text(
                                  '${iface.name}: ${iface.ip}${iface.isVirtual ? " (Virtual)" : ""}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (newIp) {
                              if (newIp != null) {
                                app.selectInterfaceIp(newIp);
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // QR Code Container
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 180.0,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E1B4B),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E1B4B),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Exact IP & Port with copy
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_rounded, size: 14, color: Color(0xFF059669)),
                    const SizedBox(width: 6),
                    Text(
                      '${payload.ip}:${payload.port}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '${payload.ip}:${payload.port}'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('IP:Port copied to clipboard'), duration: Duration(seconds: 1)),
                        );
                      },
                      child: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF059669)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 6),
              // Health URL hint
              Text(
                'Test in phone browser: http://${payload.ip}:${payload.port}/health',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace'),
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('New Key', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await app.regenerateKey();
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
