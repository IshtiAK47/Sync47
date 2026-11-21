import 'dart:convert';

/// Maximum allowed payload size: 512 KB
const int maxPayloadBytes = 512 * 1024;

class SyncPacket {
  final String type; // 'clip', 'ack', 'ping', 'hello'
  final String deviceId;
  final String deviceName;
  final int timestamp;
  final String contentType;
  final String hash;
  final String payload;

  SyncPacket({
    required this.type,
    required this.deviceId,
    required this.deviceName,
    required this.timestamp,
    this.contentType = 'text/plain',
    required this.hash,
    required this.payload,
  }) {
    if (payload.length > maxPayloadBytes * 2) {
      throw ArgumentError('Payload exceeds maximum allowed size of 512 KB.');
    }
  }

  factory SyncPacket.fromJson(Map<String, dynamic> json) {
    return SyncPacket(
      type: json['type'] as String? ?? 'clip',
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      contentType: json['content_type'] as String? ?? 'text/plain',
      hash: json['hash'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'device_id': deviceId,
    'device_name': deviceName,
    'timestamp': timestamp,
    'content_type': contentType,
    'hash': hash,
    'payload': payload,
  };

  String toJsonString() => jsonEncode(toJson());

  factory SyncPacket.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON map for SyncPacket.');
    }
    return SyncPacket.fromJson(decoded);
  }
}

class PairingPayload {
  final int version;
  final String id;
  final String name;
  final String ip;
  final int port;
  final String key;

  PairingPayload({
    this.version = 1,
    required this.id,
    required this.name,
    required this.ip,
    this.port = 47471,
    required this.key,
  });

  factory PairingPayload.fromJson(Map<String, dynamic> json) {
    return PairingPayload(
      version: json['v'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 47471,
      key: json['key'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'v': version,
    'id': id,
    'name': name,
    'ip': ip,
    'port': port,
    'key': key,
  };

  String toJsonString() => jsonEncode(toJson());

  factory PairingPayload.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON map for PairingPayload.');
    }
    return PairingPayload.fromJson(decoded);
  }
}
