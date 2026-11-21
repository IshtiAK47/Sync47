import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test('test reading clipboard via win32 without throwing', () {
    if (OpenClipboard(0) != 0) {
      try {
        final hData = GetClipboardData(CF_UNICODETEXT);
        if (hData != 0) {
          final handlePtr = Pointer<Void>.fromAddress(hData);
          final pData = GlobalLock(handlePtr);
          if (pData != nullptr) {
            try {
              final text = pData.cast<Utf16>().toDartString();
              expect(text, isA<String>());
            } finally {
              GlobalUnlock(handlePtr);
            }
          }
        }
      } finally {
        CloseClipboard();
      }
    }
  });
}
