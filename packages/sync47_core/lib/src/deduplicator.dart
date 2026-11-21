import 'dart:collection';

class _CachedHash {
  final String hash;
  final DateTime timestamp;

  _CachedHash(this.hash, this.timestamp);
}

/// Prevents infinite echo loops across devices.
/// Maintains [lastSyncedHash] plus a short-lived LRU cache of recently seen hashes.
class ClipboardDeduplicator {
  final int maxCacheSize;
  final Duration window;
  final Queue<_CachedHash> _cache = Queue<_CachedHash>();
  String? _lastSyncedHash;

  ClipboardDeduplicator({
    this.maxCacheSize = 10,
    this.window = const Duration(seconds: 5),
  });

  String? get lastSyncedHash => _lastSyncedHash;

  /// Checks if [hash] should be synced.
  /// If [hash] matches [lastSyncedHash] or was recorded within [window], returns false.
  /// Otherwise, records [hash] and returns true.
  bool shouldSync(String hash) {
    _pruneExpired();

    if (_lastSyncedHash == hash) {
      return false;
    }

    for (final item in _cache) {
      if (item.hash == hash) {
        return false;
      }
    }

    recordHash(hash);
    return true;
  }

  /// Records a hash seen locally or received remotely.
  void recordHash(String hash) {
    _lastSyncedHash = hash;
    _cache.addLast(_CachedHash(hash, DateTime.now()));
    while (_cache.length > maxCacheSize) {
      _cache.removeFirst();
    }
  }

  void _pruneExpired() {
    final now = DateTime.now();
    while (_cache.isNotEmpty && now.difference(_cache.first.timestamp) > window) {
      _cache.removeFirst();
    }
  }

  void clear() {
    _cache.clear();
    _lastSyncedHash = null;
  }
}
