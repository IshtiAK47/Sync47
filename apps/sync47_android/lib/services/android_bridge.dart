import 'package:flutter/services.dart';
import 'package:sync47_core/sync47_core.dart';
import '../models/clip_record.dart';

typedef StatusChangedHandler = void Function(String status);
typedef ClipReceivedHandler = void Function(ClipRecord clip);

class AndroidBridge {
  static const MethodChannel _channel = MethodChannel('com.sync47.app/bridge');

  StatusChangedHandler? onStatusChanged;
  ClipReceivedHandler? onClipReceived;

  AndroidBridge() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatusChanged':
        final status = call.arguments?.toString() ?? 'waiting';
        onStatusChanged?.call(status);
        break;
      case 'onClipReceived':
        if (call.arguments is Map) {
          final clip = ClipRecord.fromMap(call.arguments as Map);
          onClipReceived?.call(clip);
        }
        break;
    }
  }

  Future<bool> savePairing(PairingPayload payload) async {
    final result = await _channel.invokeMethod<bool>('savePairing', {
      'id': payload.id,
      'name': payload.name,
      'ip': payload.ip,
      'port': payload.port,
      'key': payload.key,
    });
    return result ?? false;
  }

  Future<Map<String, dynamic>> getPairingInfo() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getPairingInfo');
    return result ?? {};
  }

  Future<String> getConnectionStatus() async {
    final status = await _channel.invokeMethod<String>('getConnectionStatus');
    return status ?? 'waiting';
  }

  Future<List<ClipRecord>> getHistory() async {
    final result = await _channel.invokeListMethod<dynamic>('getHistory');
    if (result == null) return [];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map((map) => ClipRecord.fromMap(map))
        .toList();
  }

  Future<bool> deleteClip(String id) async {
    final result = await _channel.invokeMethod<bool>('deleteClip', {'id': id});
    return result ?? false;
  }

  Future<bool> clearHistory() async {
    final result = await _channel.invokeMethod<bool>('clearHistory');
    return result ?? false;
  }

  Future<bool> unpair() async {
    final result = await _channel.invokeMethod<bool>('unpair');
    return result ?? false;
  }

  Future<bool> togglePause({bool? paused}) async {
    final result = await _channel.invokeMethod<bool>('togglePause', {
      if (paused != null) 'paused': paused,
    });
    return result ?? false;
  }

  Future<bool> setAutoSyncWifi(bool enabled) async {
    final result = await _channel.invokeMethod<bool>('setAutoSyncWifi', {'enabled': enabled});
    return result ?? false;
  }

  Future<bool> setAutoSendAccessibility(bool enabled) async {
    final result = await _channel.invokeMethod<bool>('setAutoSendAccessibility', {'enabled': enabled});
    return result ?? false;
  }

  Future<bool> sendClip(String text) async {
    final result = await _channel.invokeMethod<bool>('sendClip', {'text': text});
    return result ?? false;
  }

  Future<bool> requestAddTile() async {
    final result = await _channel.invokeMethod<bool>('requestAddTile');
    return result ?? false;
  }

  Future<bool> openBatterySettings() async {
    final result = await _channel.invokeMethod<bool>('openBatterySettings');
    return result ?? false;
  }

  Future<Map<String, dynamic>> testConnection({String? ip, int? port}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('testConnection', {
      if (ip != null) 'ip': ip,
      if (port != null) 'port': port,
    });
    return result ?? {'success': false, 'message': 'Unknown error'};
  }

  Future<Map<String, dynamic>> checkPermissions() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('checkPermissions');
    return result ?? {
      'accessibilityEnabled': false,
      'overlayGranted': false,
      'readLogsGranted': false,
    };
  }

  Future<bool> openAccessibilitySettings() async {
    final result = await _channel.invokeMethod<bool>('openAccessibilitySettings');
    return result ?? false;
  }

  Future<bool> openOverlaySettings() async {
    final result = await _channel.invokeMethod<bool>('openOverlaySettings');
    return result ?? false;
  }

  Future<bool> manualPair({
    required String ip,
    required int port,
    String? name,
    String? key,
  }) async {
    final result = await _channel.invokeMethod<bool>('manualPair', {
      'ip': ip,
      'port': port,
      if (name != null) 'name': name,
      if (key != null) 'key': key,
    });
    return result ?? false;
  }
}
