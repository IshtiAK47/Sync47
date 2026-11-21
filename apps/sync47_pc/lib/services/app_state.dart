import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sync47_core/sync47_core.dart';
import 'package:uuid/uuid.dart';
import '../models/clip_item.dart';
import 'discovery_beacon.dart';
import 'settings_service.dart';
import 'sync_server.dart';
import 'windows_clipboard_watcher.dart';

enum ConnectionStatus {
  connected,
  waiting,
  paused,
}

class AppState extends ChangeNotifier {
  final SettingsService settingsService;
  final ClipboardDeduplicator deduplicator = ClipboardDeduplicator(
    maxCacheSize: 15,
    window: const Duration(seconds: 3), // 3-second loop prevention window
  );

  late final WindowsClipboardWatcher clipboardWatcher;
  late final SyncServer syncServer;
  late final DiscoveryBeacon discoveryBeacon;

  String _localIp = '127.0.0.1';
  int _port = 47471;
  String? _connectedDeviceName;
  List<ClipItem> _history = [];
  List<NetworkInterfaceInfo> _availableInterfaces = [];

  AppState({required this.settingsService}) {
    _history = settingsService.getHistory();
    _connectedDeviceName = settingsService.pairedDeviceName;

    clipboardWatcher = WindowsClipboardWatcher(
      onClipboardChanged: _onLocalClipboardChanged,
      ignorePasswordManagers: settingsService.ignorePasswordManagers,
    );

    syncServer = SyncServer(
      deviceId: settingsService.deviceId,
      deviceName: settingsService.deviceName,
      encryptionKey: settingsService.encryptionKey,
      deduplicator: deduplicator,
      onClientConnected: _onClientConnected,
      onClientDisconnected: _onClientDisconnected,
      onClipReceived: _onRemoteClipReceived,
    );

    discoveryBeacon = DiscoveryBeacon(
      deviceId: settingsService.deviceId,
      serverPort: _port,
    );
  }

  String get deviceId => settingsService.deviceId;
  String get deviceName => settingsService.deviceName;
  String get encryptionKey => settingsService.encryptionKey;
  String get localIp => _localIp;
  int get port => _port;
  String? get connectedDeviceName => _connectedDeviceName;
  List<ClipItem> get history => List.unmodifiable(_history);
  List<NetworkInterfaceInfo> get availableInterfaces => List.unmodifiable(_availableInterfaces);
  bool get isPaused => settingsService.isPaused;
  bool get launchAtStartup => settingsService.launchAtStartup;
  bool get startMinimized => settingsService.startMinimized;
  bool get ignorePasswordManagers => settingsService.ignorePasswordManagers;

  ConnectionStatus get connectionStatus {
    if (isPaused) return ConnectionStatus.paused;
    if (syncServer.connectedClientCount > 0) return ConnectionStatus.connected;
    return ConnectionStatus.waiting;
  }

  Future<void> init() async {
    _availableInterfaces = await SyncServer.getAvailableInterfaces();
    if (_availableInterfaces.isNotEmpty) {
      _localIp = _availableInterfaces.first.ip;
    } else {
      _localIp = await SyncServer.getPrimaryLocalIp();
    }

    _port = await syncServer.start(initialPort: 47471);

    // Start UDP discovery beacon
    await discoveryBeacon.start();

    // Start native zero-polling clipboard watcher
    if (!isPaused) {
      clipboardWatcher.start();
    }

    notifyListeners();
  }

  void selectInterfaceIp(String ip) {
    if (_localIp != ip) {
      _localIp = ip;
      notifyListeners();
    }
  }

  Future<void> refreshInterfaces() async {
    _availableInterfaces = await SyncServer.getAvailableInterfaces();
    notifyListeners();
  }

  void _onLocalClipboardChanged(String text) {
    if (isPaused) return;

    final hash = AesGcmCrypto.sha256Hex(text);
    if (!deduplicator.shouldSync(hash)) {
      return;
    }

    // Add to local history
    final item = ClipItem(
      id: const Uuid().v4(),
      text: text,
      hash: hash,
      source: 'laptop',
      timestamp: DateTime.now(),
    );
    _addHistoryItem(item);

    // Broadcast over WebSocket to phone
    syncServer.broadcastClip(text);
  }

  void _onRemoteClipReceived(String text, String source, int timestamp, String hash) {
    final item = ClipItem(
      id: const Uuid().v4(),
      text: text,
      hash: hash,
      source: 'phone',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    _addHistoryItem(item);
  }

  void _onClientConnected(String name, String id) {
    _connectedDeviceName = name;
    settingsService.setPairedDevice(id: id, name: name);
    notifyListeners();
  }

  void _onClientDisconnected(String id) {
    if (syncServer.connectedClientCount == 0) {
      notifyListeners();
    }
  }

  void _addHistoryItem(ClipItem item) {
    _history.removeWhere((existing) => existing.hash == item.hash);
    _history.insert(0, item);
    if (_history.length > 20) {
      _history = _history.sublist(0, 20);
    }
    settingsService.saveHistory(_history);
    notifyListeners();
  }

  Future<void> togglePause() async {
    final newPaused = !isPaused;
    await settingsService.setIsPaused(newPaused);
    if (newPaused) {
      clipboardWatcher.stop();
    } else {
      clipboardWatcher.start();
    }
    notifyListeners();
  }

  Future<void> copyClip(ClipItem item) async {
    deduplicator.recordHash(item.hash);
    await Clipboard.setData(ClipboardData(text: item.text));
  }

  Future<void> deleteClip(ClipItem item) async {
    _history.removeWhere((i) => i.id == item.id);
    await settingsService.saveHistory(_history);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await settingsService.saveHistory(_history);
    notifyListeners();
  }

  Future<void> regenerateKey() async {
    settingsService.regenerateKey();
    await syncServer.stop();
    _port = await syncServer.start(initialPort: 47471);
    notifyListeners();
  }

  Future<void> setLaunchAtStartup(bool value) async {
    await settingsService.setLaunchAtStartup(value);
    notifyListeners();
  }

  Future<void> setStartMinimized(bool value) async {
    await settingsService.setStartMinimized(value);
    notifyListeners();
  }

  Future<void> setIgnorePasswordManagers(bool value) async {
    await settingsService.setIgnorePasswordManagers(value);
    clipboardWatcher.updateIgnoreSensitive(value);
    notifyListeners();
  }

  Future<void> unpairDevice() async {
    _connectedDeviceName = null;
    await settingsService.clearPairedDevice();
    notifyListeners();
  }

  PairingPayload getPairingPayload() {
    return PairingPayload(
      version: 1,
      id: deviceId,
      name: deviceName,
      ip: localIp,
      port: port,
      key: encryptionKey,
    );
  }

  @override
  void dispose() {
    clipboardWatcher.stop();
    discoveryBeacon.stop();
    syncServer.stop();
    super.dispose();
  }
}
