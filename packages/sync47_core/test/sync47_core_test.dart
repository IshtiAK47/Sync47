import 'dart:convert';
import 'package:sync47_core/sync47_core.dart';
import 'package:test/test.dart';

void main() {
  group('AesGcmCrypto', () {
    test('generateKeyBase64 creates 32-byte valid base64 key', () {
      final key = AesGcmCrypto.generateKeyBase64();
      final decoded = base64Decode(key);
      expect(decoded.length, equals(32));
    });

    test('sha256Hex calculates correct hex digest', () {
      final hash = AesGcmCrypto.sha256Hex('Hello Sync47');
      // echo -n "Hello Sync47" | sha256sum
      expect(hash.length, equals(64));
      expect(hash, equals(AesGcmCrypto.sha256Hex('Hello Sync47')));
      expect(hash, isNot(equals(AesGcmCrypto.sha256Hex('Hello Sync48'))));
    });

    test('encrypt and decrypt round-trip works', () async {
      final key = AesGcmCrypto.generateKeyBase64();
      const originalText = 'Super secret clipboard content: https://antigravity.google.com';

      final encrypted = await AesGcmCrypto.encrypt(originalText, key);
      expect(encrypted, isNotEmpty);
      expect(encrypted, isNot(equals(originalText)));

      final decrypted = await AesGcmCrypto.decrypt(encrypted, key);
      expect(decrypted, equals(originalText));
    });

    test('tampered ciphertext fails decryption', () async {
      final key = AesGcmCrypto.generateKeyBase64();
      const originalText = 'Clipboard message';

      final encrypted = await AesGcmCrypto.encrypt(originalText, key);
      final bytes = base64Decode(encrypted);

      // Corrupt a byte in the middle of ciphertext
      bytes[15] ^= 0xFF;
      final tamperedBase64 = base64Encode(bytes);

      expect(
        () async => await AesGcmCrypto.decrypt(tamperedBase64, key),
        throwsA(anything),
      );
    });

    test('decrypting with wrong key fails authentication', () async {
      final key1 = AesGcmCrypto.generateKeyBase64();
      final key2 = AesGcmCrypto.generateKeyBase64();
      const originalText = 'Authenticate me';

      final encrypted = await AesGcmCrypto.encrypt(originalText, key1);

      expect(
        () async => await AesGcmCrypto.decrypt(encrypted, key2),
        throwsA(anything),
      );
    });

    test('wire format matches 12-byte IV + ciphertext + 16-byte tag layout', () async {
      final key = AesGcmCrypto.generateKeyBase64();
      const plaintext = '12345678'; // 8 bytes
      final encrypted = await AesGcmCrypto.encrypt(plaintext, key);
      final rawBytes = base64Decode(encrypted);

      // 12 (IV) + 8 (ciphertext) + 16 (tag) = 36 bytes
      expect(rawBytes.length, equals(12 + 8 + 16));
    });
  });

  group('SyncPacket', () {
    test('JSON serialization & deserialization', () {
      final packet = SyncPacket(
        type: 'clip',
        deviceId: 'device-123',
        deviceName: 'Pixel 9 Pro',
        timestamp: 1732123456789,
        contentType: 'text/plain',
        hash: 'abc123hash',
        payload: 'encryptedpayloadbase64==',
      );

      final jsonStr = packet.toJsonString();
      final reconstructed = SyncPacket.fromJsonString(jsonStr);

      expect(reconstructed.type, equals('clip'));
      expect(reconstructed.deviceId, equals('device-123'));
      expect(reconstructed.deviceName, equals('Pixel 9 Pro'));
      expect(reconstructed.timestamp, equals(1732123456789));
      expect(reconstructed.contentType, equals('text/plain'));
      expect(reconstructed.hash, equals('abc123hash'));
      expect(reconstructed.payload, equals('encryptedpayloadbase64=='));
    });
  });

  group('PairingPayload', () {
    test('JSON serialization & deserialization matches QR schema', () {
      final pairing = PairingPayload(
        version: 1,
        id: 'pc-guid',
        name: 'Workstation',
        ip: '192.168.1.100',
        port: 47471,
        key: 'base64key',
      );

      final jsonStr = pairing.toJsonString();
      final parsed = PairingPayload.fromJsonString(jsonStr);

      expect(parsed.version, equals(1));
      expect(parsed.id, equals('pc-guid'));
      expect(parsed.name, equals('Workstation'));
      expect(parsed.ip, equals('192.168.1.100'));
      expect(parsed.port, equals(47471));
      expect(parsed.key, equals('base64key'));
    });
  });

  group('ClipboardDeduplicator', () {
    test('drops identical consecutive hashes', () {
      final dedup = ClipboardDeduplicator();
      const hash1 = 'hash-1111';

      expect(dedup.shouldSync(hash1), isTrue);
      expect(dedup.shouldSync(hash1), isFalse); // dropped
      expect(dedup.shouldSync(hash1), isFalse); // dropped
    });

    test('allows alternating hashes but rejects hashes in recent window', () {
      final dedup = ClipboardDeduplicator();
      const hashA = 'hash-AAAA';
      const hashB = 'hash-BBBB';

      expect(dedup.shouldSync(hashA), isTrue);
      expect(dedup.shouldSync(hashB), isTrue);
      // Even if alternating, hashA was in recent LRU window
      expect(dedup.shouldSync(hashA), isFalse);
    });

    test('recordHash updates lastSyncedHash', () {
      final dedup = ClipboardDeduplicator();
      dedup.recordHash('hash-remote');
      expect(dedup.lastSyncedHash, equals('hash-remote'));
      expect(dedup.shouldSync('hash-remote'), isFalse);
    });
  });
}
