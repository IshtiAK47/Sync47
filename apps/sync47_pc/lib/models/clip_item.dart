import 'dart:convert';

class ClipItem {
  final String id;
  final String text;
  final String hash;
  final String source; // 'phone' or 'laptop'
  final DateTime timestamp;

  ClipItem({
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'hash': hash,
    'source': source,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory ClipItem.fromJson(Map<String, dynamic> json) => ClipItem(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    hash: json['hash'] as String? ?? '',
    source: json['source'] as String? ?? 'laptop',
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );

  String toJsonString() => jsonEncode(toJson());

  factory ClipItem.fromJsonString(String source) =>
      ClipItem.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
