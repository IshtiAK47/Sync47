import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/android_app_state.dart';

class QrScannerScreen extends StatefulWidget {
  final AndroidAppState appState;

  const QrScannerScreen({super.key, required this.appState});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        setState(() => _isProcessing = true);
        final success = await widget.appState.pairFromQr(rawValue);
        if (!mounted) return;

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Paired with PC successfully!'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid QR code. Please scan the QR from Sync47 PC.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          setState(() => _isProcessing = false);
        }
        break;
      }
    }
  }

  void _showManualIpDialog(BuildContext context) {
    final nav = Navigator.of(context);
    final ipController = TextEditingController(text: widget.appState.pcIp);
    final portController = TextEditingController(text: widget.appState.pcPort.toString());

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
                  final success = await widget.appState.manualPair(ip: ip, port: port);
                  if (mounted && success) {
                    nav.pop(true);
                  }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan PC QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Toggle Flash',
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'Enter IP Manually',
            onPressed: () => _showManualIpDialog(context),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF4F46E5), width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Positioned(
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Point camera at the Sync47 QR on your PC',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
              ),
            ),
        ],
      ),
    );
  }
}
