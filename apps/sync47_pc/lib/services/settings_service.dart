import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync47_core/sync47_core.dart';
import 'package:uuid/uuid.dart';
import '../models/clip_item.dart';

class SettingsService {
  static const String _keyDeviceId = 'device_id';
  static const String _keyDeviceName = 'device_name';
  static const String _keyEncryptionKey = 'encryption_key';
  static const String _keyLaunchAtStartup = 'launch_at_startup';
  static const String _keyStartMinimized = 'start_minimized';
  static const String _keyIgnorePasswordManagers = 'ignore_password_managers';
  static const String _keyIsPaused = 'is_paused';
  static const String _keyPairedDeviceId = 'paired_device_id';
  static const String _keyPairedDeviceName = 'paired_device_name';
  static const String _keyClipHistory = 'clip_history';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  String get deviceId {
    var id = _prefs.getString(_keyDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      _prefs.setString(_keyDeviceId, id);
    }
    return id;
  }

  String get deviceName {
    var name = _prefs.getString(_keyDeviceName);
    if (name == null || name.isEmpty) {
      name = Platform.localHostname;
      if (name.isEmpty) name = 'PC Workstation';
      _prefs.setString(_keyDeviceName, name);
    }
    return name;
  }

  Future<void> setDeviceName(String name) async {
    await _prefs.setString(_keyDeviceName, name);
  }

  String get encryptionKey {
    var key = _prefs.getString(_keyEncryptionKey);
    if (key == null || key.isEmpty) {
      key = AesGcmCrypto.generateKeyBase64();
      _prefs.setString(_keyEncryptionKey, key);
    }
    return key;
  }

  Future<void> setEncryptionKey(String key) async {
    await _prefs.setString(_keyEncryptionKey, key);
  }

  String regenerateKey() {
    final newKey = AesGcmCrypto.generateKeyBase64();
    _prefs.setString(_keyEncryptionKey, newKey);
    return newKey;
  }

  bool get launchAtStartup => _prefs.getBool(_keyLaunchAtStartup) ?? false;
  Future<void> setLaunchAtStartup(bool value) async {
    await _prefs.setBool(_keyLaunchAtStartup, value);
  }

  bool get startMinimized => _prefs.getBool(_keyStartMinimized) ?? false;
  Future<void> setStartMinimized(bool value) async {
    await _prefs.setBool(_keyStartMinimized, value);
  }

  bool get ignorePasswordManagers => _prefs.getBool(_keyIgnorePasswordManagers) ?? true;
  Future<void> setIgnorePasswordManagers(bool value) async {
    await _prefs.setBool(_keyIgnorePasswordManagers, value);
  }

  bool get isPaused => _prefs.getBool(_keyIsPaused) ?? false;
  Future<void> setIsPaused(bool value) async {
    await _prefs.setBool(_keyIsPaused, value);
  }

  String? get pairedDeviceId => _prefs.getString(_keyPairedDeviceId);
  String? get pairedDeviceName => _prefs.getString(_keyPairedDeviceName);

  Future<void> setPairedDevice({required String id, required String name}) async {
    await _prefs.setString(_keyPairedDeviceId, id);
    await _prefs.setString(_keyPairedDeviceName, name);
  }

  Future<void> clearPairedDevice() async {
    await _prefs.remove(_keyPairedDeviceId);
    await _prefs.remove(_keyPairedDeviceName);
  }

  List<ClipItem> getHistory() {
    final list = _prefs.getStringList(_keyClipHistory) ?? [];
    final items = <ClipItem>[];
    for (final raw in list) {
      try {
        items.add(ClipItem.fromJsonString(raw));
      } catch (_) {}
    }
    return items;
  }

  Future<void> saveHistory(List<ClipItem> history) async {
    // Keep max 20 items
    final toSave = history.take(20).map((item) => item.toJsonString()).toList();
    await _prefs.setStringList(_keyClipHistory, toSave);
  }
}
