class ClipRecord {
  final String id;
  final String text;
  final String hash;
  final String source; // 'phone' or 'laptop'
  final DateTime timestamp;

  ClipRecord({
    required this.id,
    required this.text,
    required this.hash,
    required this.source,
    required this.timestamp,
  });

  bool get isUrl {
    final trimmed = text.trim();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  factory ClipRecord.fromMap(Map<dynamic, dynamic> map) {
    return ClipRecord(
      id: map['id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      hash: map['hash']?.toString() ?? '',
      source: map['source']?.toString() ?? 'laptop',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
