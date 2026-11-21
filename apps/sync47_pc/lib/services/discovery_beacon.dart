import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Emits UDP broadcast beacon on port 47470 every 5 seconds when unlinked or reconnecting.
/// Schema: {"app":"sync47","deviceId":"...","port":47471}
class DiscoveryBeacon {
  final String deviceId;
  final int serverPort;
  static const int beaconPort = 47470;

  Timer? _timer;
  RawDatagramSocket? _socket;
  bool _isRunning = false;

  DiscoveryBeacon({
    required this.deviceId,
    required this.serverPort,
  });

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;

    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket?.broadcastEnabled = true;
      _isRunning = true;

      // Broadcast immediately and then every 5 seconds
      _broadcastBeacon();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        _broadcastBeacon();
      });
      debugPrint('[DiscoveryBeacon] UDP broadcast beacon started on port $beaconPort.');
    } catch (e) {
      debugPrint('[DiscoveryBeacon] Error binding UDP socket: $e');
    }
  }

  void _broadcastBeacon() {
    if (_socket == null || !_isRunning) return;

    final message = jsonEncode({
      'app': 'sync47',
      'deviceId': deviceId,
      'port': serverPort,
    });

    final data = utf8.encode(message);
    try {
      final broadcastAddress = InternetAddress('255.255.255.255');
      _socket?.send(data, broadcastAddress, beaconPort);
    } catch (e) {
      debugPrint('[DiscoveryBeacon] Error sending broadcast packet: $e');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
    _isRunning = false;
    debugPrint('[DiscoveryBeacon] UDP broadcast beacon stopped.');
  }
}
