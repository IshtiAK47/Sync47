import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sync47_core/sync47_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef ClientConnectedCallback = void Function(String deviceName, String deviceId);
typedef ClientDisconnectedCallback = void Function(String deviceId);
typedef ClipReceivedCallback = void Function(String text, String source, int timestamp, String hash);

class NetworkInterfaceInfo {
  final String name;
  final String ip;
  final bool isVirtual;

  NetworkInterfaceInfo({
    required this.name,
    required this.ip,
    required this.isVirtual,
  });

  @override
  String toString() => '$name ($ip)${isVirtual ? " [Virtual]" : ""}';
}

class SyncServer {
  final String deviceId;
  final String deviceName;
  final String encryptionKey;
  final ClipboardDeduplicator deduplicator;
  final ClientConnectedCallback onClientConnected;
  final ClientDisconnectedCallback onClientDisconnected;
  final ClipReceivedCallback onClipReceived;

  HttpServer? _server;
  int _actualPort = 47471;
  final Set<WebSocketChannel> _clients = {};
  final Map<WebSocketChannel, String> _clientIds = {};
  final Map<WebSocketChannel, String> _clientNames = {};

  SyncServer({
    required this.deviceId,
    required this.deviceName,
    required this.encryptionKey,
    required this.deduplicator,
    required this.onClientConnected,
    required this.onClientDisconnected,
    required this.onClipReceived,
  });

  int get port => _actualPort;
  bool get isRunning => _server != null;
  int get connectedClientCount => _clients.length;

  Future<int> start({int initialPort = 47471}) async {
    if (_server != null) return _actualPort;

    final wsHandler = webSocketHandler((WebSocketChannel webSocket) {
      _handleNewConnection(webSocket);
    });

    final corsHeaders = {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET, POST, OPTIONS',
      'access-control-allow-headers': '*',
    };

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler((Request request) async {
      // 1. Health check for Android connectivity testing
      if (request.url.path == 'health') {
        return Response.ok(
          jsonEncode({
            'status': 'ok',
            'app': 'sync47',
            'deviceName': deviceName,
            'port': _actualPort,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
          headers: corsHeaders,
        );
      }

      // 2. WebSocket upgrade
      if (request.url.path == 'ws') {
        return wsHandler(request);
      }

      // 3. Status check
      if (request.url.path == 'status') {
        return Response.ok(
          jsonEncode({
            'app': 'sync47',
            'status': 'running',
            'id': deviceId,
            'name': deviceName,
            'port': _actualPort,
          }),
          headers: corsHeaders,
        );
      }

      return Response.notFound('Sync47 Server');
    });

    int port = initialPort;
    while (port < initialPort + 10) {
      try {
        // Explicitly bind to 0.0.0.0 (all IPv4 interfaces on LAN)
        _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
        _actualPort = port;
        debugPrint('[SyncServer] Listening on 0.0.0.0:$_actualPort');
        return _actualPort;
      } catch (e) {
        debugPrint('[SyncServer] Port $port busy, trying next port: $e');
        port++;
      }
    }

    throw StateError('Could not bind SyncServer to any port between $initialPort and ${port - 1}');
  }

  void _handleNewConnection(WebSocketChannel channel) {
    _clients.add(channel);
    debugPrint('[SyncServer] Client connected. Total clients: ${_clients.length}');

    channel.stream.listen(
      (message) async {
        try {
          if (message is! String) return;
          final packet = SyncPacket.fromJsonString(message);

          if (packet.type == 'hello') {
            _clientIds[channel] = packet.deviceId;
            _clientNames[channel] = packet.deviceName;
            onClientConnected(packet.deviceName, packet.deviceId);

            // Respond with ack hello
            final ackPacket = SyncPacket(
              type: 'ack',
              deviceId: deviceId,
              deviceName: deviceName,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              hash: '',
              payload: '',
            );
            channel.sink.add(ackPacket.toJsonString());
          } else if (packet.type == 'clip') {
            // Echo-loop guard
            if (!deduplicator.shouldSync(packet.hash)) {
              debugPrint('[SyncServer] Dropping duplicate clip hash: ${packet.hash}');
              return;
            }

            try {
              final decrypted = await AesGcmCrypto.decrypt(packet.payload, encryptionKey);
              deduplicator.recordHash(packet.hash);

              // Update system clipboard
              await Clipboard.setData(ClipboardData(text: decrypted));

              final srcName = packet.deviceName.isNotEmpty ? packet.deviceName : 'Phone';
              onClipReceived(decrypted, srcName, packet.timestamp, packet.hash);

              // Send ack
              final ack = SyncPacket(
                type: 'ack',
                deviceId: deviceId,
                deviceName: deviceName,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                hash: packet.hash,
                payload: '',
              );
              channel.sink.add(ack.toJsonString());
            } catch (decryptErr) {
              debugPrint('[SyncServer] Decryption failed for incoming clip: $decryptErr');
            }
          } else if (packet.type == 'ping') {
            final pong = SyncPacket(
              type: 'ack',
              deviceId: deviceId,
              deviceName: deviceName,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              hash: 'pong',
              payload: '',
            );
            channel.sink.add(pong.toJsonString());
          }
        } catch (e) {
          debugPrint('[SyncServer] Error processing incoming packet: $e');
        }
      },
      onDone: () {
        final id = _clientIds.remove(channel) ?? '';
        _clientNames.remove(channel);
        _clients.remove(channel);
        if (id.isNotEmpty) {
          onClientDisconnected(id);
        }
        debugPrint('[SyncServer] Client disconnected. Remaining: ${_clients.length}');
      },
      onError: (error) {
        debugPrint('[SyncServer] WebSocket channel error: $error');
        channel.sink.close();
      },
    );
  }

  /// Encrypts and broadcasts [text] to all connected clients.
  Future<void> broadcastClip(String text) async {
    if (_clients.isEmpty) return;

    final hash = AesGcmCrypto.sha256Hex(text);
    if (!deduplicator.shouldSync(hash)) {
      debugPrint('[SyncServer] Dropping local clip duplicate: $hash');
      return;
    }

    try {
      final encryptedPayload = await AesGcmCrypto.encrypt(text, encryptionKey);
      final packet = SyncPacket(
        type: 'clip',
        deviceId: deviceId,
        deviceName: deviceName,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        contentType: 'text/plain',
        hash: hash,
        payload: encryptedPayload,
      );

      final message = packet.toJsonString();
      for (final client in _clients.toList()) {
        try {
          client.sink.add(message);
        } catch (e) {
          debugPrint('[SyncServer] Failed to send to client: $e');
        }
      }
      debugPrint('[SyncServer] Broadcasted clip to ${_clients.length} client(s).');
    } catch (e) {
      debugPrint('[SyncServer] Error broadcasting clip: $e');
    }
  }

  static bool isVirtualAdapter(String name) {
    final lower = name.toLowerCase();
    return lower.contains('vethernet') ||
        lower.contains('wsl') ||
        lower.contains('hyper-v') ||
        lower.contains('virtual') ||
        lower.contains('vmware') ||
        lower.contains('tailscale') ||
        lower.contains('zerotier') ||
        lower.contains('loopback') ||
        lower.contains('docker') ||
        lower.contains('npcap') ||
        lower.contains('tap') ||
        lower.contains('tun') ||
        lower.contains('pseudo');
  }

  /// Returns all available IPv4 network interfaces categorized.
  static Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async {
    final result = <NetworkInterfaceInfo>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        final isVirt = isVirtualAdapter(iface.name);
        for (final addr in iface.addresses) {
          result.add(NetworkInterfaceInfo(
            name: iface.name,
            ip: addr.address,
            isVirtual: isVirt,
          ));
        }
      }

      // Sort priority:
      // 1. Non-virtual 192.168.x.x (typical Wi-Fi / home LAN)
      // 2. Non-virtual 10.x.x.x
      // 3. Other non-virtual
      // 4. Virtual
      result.sort((a, b) {
        if (!a.isVirtual && b.isVirtual) return -1;
        if (a.isVirtual && !b.isVirtual) return 1;

        final aIs192 = a.ip.startsWith('192.168.');
        final bIs192 = b.ip.startsWith('192.168.');
        if (aIs192 && !bIs192) return -1;
        if (!aIs192 && bIs192) return 1;

        final aIs10 = a.ip.startsWith('10.');
        final bIs10 = b.ip.startsWith('10.');
        if (aIs10 && !bIs10) return -1;
        if (!aIs10 && bIs10) return 1;

        return a.name.compareTo(b.name);
      });
    } catch (e) {
      debugPrint('[SyncServer] Error enumerating network interfaces: $e');
    }
    return result;
  }

  /// Discovers best primary local LAN IPv4 address (filtering out virtual adapters).
  static Future<String> getPrimaryLocalIp() async {
    final ifaces = await getAvailableInterfaces();
    if (ifaces.isNotEmpty) {
      return ifaces.first.ip;
    }
    return '127.0.0.1';
  }

  Future<void> stop() async {
    for (final client in _clients.toList()) {
      await client.sink.close();
    }
    _clients.clear();
    _clientIds.clear();
    _clientNames.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint('[SyncServer] Stopped.');
  }
}
