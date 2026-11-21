import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sync47_core/sync47_core.dart';
import '../models/clip_record.dart';
import '../services/android_bridge.dart';

class AndroidAppState extends ChangeNotifier {
  final AndroidBridge bridge;

  bool _isPaired = false;
  String _pcName = 'PC Workstation';
  String _pcIp = '';
  int _pcPort = 47471;
  String _status = 'waiting';
  bool _isPaused = false;
  bool _autoSyncWifi = true;
  bool _autoSendAccessibility = false;
  List<ClipRecord> _history = [];
  bool _isLoading = true;

  // Permissions & Diagnostics
  bool _accessibilityEnabled = false;
  bool _overlayGranted = false;
  bool _readLogsGranted = false;
  bool _isTestingConnection = false;
  String? _testConnectionResult;
  bool? _testConnectionSuccess;

  AndroidAppState({required this.bridge}) {
    bridge.onStatusChanged = (status) {
      _status = status;
      notifyListeners();
    };

    bridge.onClipReceived = (clip) {
      _history.removeWhere((c) => c.hash == clip.hash);
      _history.insert(0, clip);
      if (_history.length > 20) {
        _history = _history.sublist(0, 20);
      }
      notifyListeners();
    };
  }

  bool get isPaired => _isPaired;
  String get pcName => _pcName;
  String get pcIp => _pcIp;
  int get pcPort => _pcPort;
  String get status => _status;
  bool get isPaused => _isPaused;
  bool get autoSyncWifi => _autoSyncWifi;
  bool get autoSendAccessibility => _autoSendAccessibility;
  List<ClipRecord> get history => List.unmodifiable(_history);
  bool get isLoading => _isLoading;

  bool get accessibilityEnabled => _accessibilityEnabled;
  bool get overlayGranted => _overlayGranted;
  bool get readLogsGranted => _readLogsGranted;
  bool get isTestingConnection => _isTestingConnection;
  String? get testConnectionResult => _testConnectionResult;
  bool? get testConnectionSuccess => _testConnectionSuccess;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final info = await bridge.getPairingInfo();
      _isPaired = info['isPaired'] == true;
      _pcName = info['name']?.toString() ?? 'PC Workstation';
      _pcIp = info['ip']?.toString() ?? '';
      _pcPort = (info['port'] as num?)?.toInt() ?? 47471;
      _isPaused = info['isPaused'] == true;
      _autoSyncWifi = info['autoSyncWifi'] != false;
      _autoSendAccessibility = info['autoSendAccessibility'] == true;

      _status = await bridge.getConnectionStatus();
      _history = await bridge.getHistory();
      await checkPermissions();
    } catch (e) {
      debugPrint('[AndroidAppState] Error initializing: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> checkPermissions() async {
    try {
      final perms = await bridge.checkPermissions();
      _accessibilityEnabled = perms['accessibilityEnabled'] == true;
      _overlayGranted = perms['overlayGranted'] == true;
      _readLogsGranted = perms['readLogsGranted'] == true;
      notifyListeners();
    } catch (e) {
      debugPrint('[AndroidAppState] Error checking permissions: $e');
    }
  }

  Future<Map<String, dynamic>> testConnection({String? ip, int? port}) async {
    _isTestingConnection = true;
    _testConnectionResult = null;
    _testConnectionSuccess = null;
    notifyListeners();

    try {
      final res = await bridge.testConnection(ip: ip ?? _pcIp, port: port ?? _pcPort);
      _testConnectionSuccess = res['success'] == true;
      _testConnectionResult = res['message']?.toString() ?? 'Done';
      return res;
    } catch (e) {
      _testConnectionSuccess = false;
      _testConnectionResult = e.toString();
      return {'success': false, 'message': e.toString()};
    } finally {
      _isTestingConnection = false;
      notifyListeners();
    }
  }

  Future<bool> manualPair({
    required String ip,
    required int port,
    String? name,
    String? key,
  }) async {
    try {
      final success = await bridge.manualPair(
        ip: ip,
        port: port,
        name: name,
        key: key,
      );
      if (success) {
        _isPaired = true;
        _pcIp = ip;
        _pcPort = port;
        if (name != null) _pcName = name;
        _status = 'connecting';
        notifyListeners();
        await testConnection();
        return true;
      }
    } catch (e) {
      debugPrint('[AndroidAppState] Error manual pair: $e');
    }
    return false;
  }

  Future<void> openAccessibilitySettings() async {
    await bridge.openAccessibilitySettings();
    await Future.delayed(const Duration(milliseconds: 600));
    await checkPermissions();
  }

  Future<void> openOverlaySettings() async {
    await bridge.openOverlaySettings();
    await Future.delayed(const Duration(milliseconds: 600));
    await checkPermissions();
  }

  Future<bool> pairFromQr(String qrContent) async {
    try {
      final payload = PairingPayload.fromJsonString(qrContent);
      final success = await bridge.savePairing(payload);
      if (success) {
        _isPaired = true;
        _pcName = payload.name;
        _pcIp = payload.ip;
        _pcPort = payload.port;
        _status = 'connecting';
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[AndroidAppState] Error pairing QR: $e');
    }
    return false;
  }

  Future<bool> sendCurrentClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return false;

    final success = await bridge.sendClip(text);
    if (success) {
      _history = await bridge.getHistory();
      notifyListeners();
    }
    return success;
  }

  Future<void> copyClip(ClipRecord clip) async {
    await Clipboard.setData(ClipboardData(text: clip.text));
  }

  Future<void> deleteClip(String id) async {
    await bridge.deleteClip(id);
    _history.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await bridge.clearHistory();
    _history.clear();
    notifyListeners();
  }

  Future<void> unpair() async {
    await bridge.unpair();
    _isPaired = false;
    _pcName = '';
    _pcIp = '';
    _status = 'disconnected';
    notifyListeners();
  }

  Future<void> togglePause() async {
    final newPaused = !_isPaused;
    _isPaused = await bridge.togglePause(paused: newPaused);
    notifyListeners();
  }

  Future<void> setAutoSyncWifi(bool enabled) async {
    _autoSyncWifi = enabled;
    await bridge.setAutoSyncWifi(enabled);
    notifyListeners();
  }

  Future<void> setAutoSendAccessibility(bool enabled) async {
    _autoSendAccessibility = enabled;
    await bridge.setAutoSendAccessibility(enabled);
    notifyListeners();
  }

  Future<bool> requestAddTile() async {
    return await bridge.requestAddTile();
  }

  Future<bool> openBatterySettings() async {
    return await bridge.openBatterySettings();
  }
}
