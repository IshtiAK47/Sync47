import 'package:sync47_core/sync47_core.dart';

void main() async {
  final key = AesGcmCrypto.generateKeyBase64();
  final encrypted = await AesGcmCrypto.encrypt('Hello Sync47!', key);
  final decrypted = await AesGcmCrypto.decrypt(encrypted, key);
  print('Decrypted: $decrypted');
}
