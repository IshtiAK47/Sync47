import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

typedef ClipboardChangeCallback = void Function(String text);

// Global static reference for the Win32 window procedure
ClipboardChangeCallback? _globalClipboardCallback;
bool _globalIgnoreSensitive = true;

int _clipboardWndProc(int hwnd, int uMsg, int wParam, int lParam) {
  if (uMsg == WM_CLIPBOARDUPDATE) {
    if (_isSensitiveClipboard()) {
      debugPrint('[WindowsClipboardWatcher] Ignored sensitive clipboard format (password manager).');
      return 0;
    }

    final text = _readClipboardUnicodeText();
    if (text != null && text.isNotEmpty) {
      _globalClipboardCallback?.call(text);
    }
    return 0;
  }
  return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

bool _isSensitiveClipboard() {
  if (!_globalIgnoreSensitive) return false;

  try {
    // 1. ExcludeClipboardContentFromMonitorProcessing
    final excludeName = 'ExcludeClipboardContentFromMonitorProcessing'.toNativeUtf16();
    final excludeId = RegisterWindowMessage(excludeName);
    free(excludeName);

    if (excludeId != 0 && IsClipboardFormatAvailable(excludeId) != 0) {
      return true;
    }

    // 2. CanIncludeInClipboardHistory
    final canIncludeName = 'CanIncludeInClipboardHistory'.toNativeUtf16();
    final canIncludeId = RegisterWindowMessage(canIncludeName);
    free(canIncludeName);

    if (canIncludeId != 0 && IsClipboardFormatAvailable(canIncludeId) != 0) {
      if (OpenClipboard(0) != 0) {
        try {
          final hData = GetClipboardData(canIncludeId);
          if (hData != 0) {
            final pData = GlobalLock(Pointer<Void>.fromAddress(hData));
            if (pData != nullptr) {
              final val = pData.cast<Uint32>().value;
              GlobalUnlock(Pointer<Void>.fromAddress(hData));
              if (val == 0) {
                return true; // Password manager marked as Do Not Include in History
              }
            }
          }
        } finally {
          CloseClipboard();
        }
      }
    }
  } catch (e) {
    debugPrint('[WindowsClipboardWatcher] Error checking sensitive formats: $e');
  }

  return false;
}

String? _readClipboardUnicodeText() {
  if (OpenClipboard(0) == 0) return null;
  try {
    final hData = GetClipboardData(CF_UNICODETEXT);
    if (hData == 0) return null;

    final handlePtr = Pointer<Void>.fromAddress(hData);
    final pData = GlobalLock(handlePtr);
    if (pData == nullptr) return null;

    try {
      return pData.cast<Utf16>().toDartString();
    } finally {
      GlobalUnlock(handlePtr);
    }
  } catch (e) {
    debugPrint('[WindowsClipboardWatcher] Error reading clipboard: $e');
    return null;
  } finally {
    CloseClipboard();
  }
}

/// Zero-polling Windows clipboard watcher using Win32 HWND_MESSAGE
/// and AddClipboardFormatListener. 0% idle CPU.
class WindowsClipboardWatcher {
  final ClipboardChangeCallback onClipboardChanged;
  bool ignorePasswordManagers;

  int _hwnd = 0;
  Pointer<Utf16>? _className;
  Pointer<WNDCLASS>? _wndClass;
  bool _isListening = false;

  WindowsClipboardWatcher({
    required this.onClipboardChanged,
    this.ignorePasswordManagers = true,
  });

  bool get isListening => _isListening;

  void start() {
    if (!Platform.isWindows) {
      debugPrint('[WindowsClipboardWatcher] Non-Windows OS detected; native hook inactive.');
      return;
    }
    if (_isListening) return;

    _globalClipboardCallback = onClipboardChanged;
    _globalIgnoreSensitive = ignorePasswordManagers;

    try {
      final uniqueName = 'Sync47ClipboardListener_${DateTime.now().microsecondsSinceEpoch}';
      _className = uniqueName.toNativeUtf16();
      final lpfn = Pointer.fromFunction<WNDPROC>(_clipboardWndProc, 0);

      _wndClass = calloc<WNDCLASS>()
        ..ref.lpfnWndProc = lpfn
        ..ref.hInstance = GetModuleHandle(nullptr)
        ..ref.lpszClassName = _className!;

      final atom = RegisterClass(_wndClass!);
      if (atom == 0) {
        debugPrint('[WindowsClipboardWatcher] Failed to register window class.');
        return;
      }

      _hwnd = CreateWindowEx(
        0,
        _className!,
        _className!,
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        0,
        GetModuleHandle(nullptr),
        nullptr,
      );

      if (_hwnd == 0) {
        debugPrint('[WindowsClipboardWatcher] Failed to create HWND_MESSAGE window.');
        return;
      }

      final success = AddClipboardFormatListener(_hwnd);
      if (success == TRUE) {
        _isListening = true;
        debugPrint('[WindowsClipboardWatcher] Native zero-polling clipboard hook active.');
      } else {
        debugPrint('[WindowsClipboardWatcher] AddClipboardFormatListener failed.');
      }
    } catch (e) {
      debugPrint('[WindowsClipboardWatcher] Exception initializing Win32 listener: $e');
    }
  }

  void updateIgnoreSensitive(bool value) {
    ignorePasswordManagers = value;
    _globalIgnoreSensitive = value;
  }

  void stop() {
    if (!_isListening) return;

    try {
      if (_hwnd != 0) {
        RemoveClipboardFormatListener(_hwnd);
        DestroyWindow(_hwnd);
        _hwnd = 0;
      }
      if (_className != null) {
        UnregisterClass(_className!, GetModuleHandle(nullptr));
        free(_className!);
        _className = null;
      }
      if (_wndClass != null) {
        free(_wndClass!);
        _wndClass = null;
      }
      _globalClipboardCallback = null;
      _isListening = false;
      debugPrint('[WindowsClipboardWatcher] Native clipboard hook stopped.');
    } catch (e) {
      debugPrint('[WindowsClipboardWatcher] Error stopping listener: $e');
    }
  }
}
