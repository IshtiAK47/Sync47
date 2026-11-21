import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

class AesGcmCrypto {
  static final AesGcm _aesGcm = AesGcm.with256bits();

  /// Calculates the SHA-256 hex digest of the given plaintext.
  static String sha256Hex(String text) {
    return crypto.sha256.convert(utf8.encode(text)).toString();
  }

  /// Generates a cryptographically secure random 256-bit (32-byte) key as Base64.
  static String generateKeyBase64() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Encode(bytes);
  }

  /// Encrypts [plaintext] using AES-256-GCM with [keyBase64].
  /// Wire format: Base64( 12-byte random IV || ciphertext || 16-byte GCM authentication tag )
  static Future<String> encrypt(String plaintext, String keyBase64) async {
    final keyBytes = base64Decode(keyBase64);
    if (keyBytes.length != 32) {
      throw ArgumentError('AES-256 key must be exactly 32 bytes (decoded).');
    }

    final secretKey = SecretKey(keyBytes);
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
    );

    final iv = secretBox.nonce; // 12 bytes
    final cipherText = secretBox.cipherText;
    final tag = secretBox.mac.bytes; // 16 bytes

    final totalLength = iv.length + cipherText.length + tag.length;
    final buffer = Uint8List(totalLength);
    buffer.setRange(0, iv.length, iv);
    buffer.setRange(iv.length, iv.length + cipherText.length, cipherText);
    buffer.setRange(iv.length + cipherText.length, totalLength, tag);

    return base64Encode(buffer);
  }

  /// Decrypts [base64Payload] using AES-256-GCM with [keyBase64].
  /// Expects payload layout: Base64( 12-byte IV || ciphertext || 16-byte GCM tag )
  static Future<String> decrypt(String base64Payload, String keyBase64) async {
    final keyBytes = base64Decode(keyBase64);
    if (keyBytes.length != 32) {
      throw ArgumentError('AES-256 key must be exactly 32 bytes (decoded).');
    }

    final rawBytes = base64Decode(base64Payload);
    // Minimum length is 12 (IV) + 16 (tag) = 28 bytes (empty plaintext)
    if (rawBytes.length < 28) {
      throw const FormatException('Payload is too short to contain IV and GCM tag.');
    }

    final iv = rawBytes.sublist(0, 12);
    final tag = rawBytes.sublist(rawBytes.length - 16);
    final cipherText = rawBytes.sublist(12, rawBytes.length - 16);

    final secretKey = SecretKey(keyBytes);
    final secretBox = SecretBox(
      cipherText,
      nonce: iv,
      mac: Mac(tag),
    );

    final decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(decryptedBytes);
  }
}
