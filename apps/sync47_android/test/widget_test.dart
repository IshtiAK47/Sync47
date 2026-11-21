import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync47_android/main.dart';
import 'package:sync47_android/providers/android_app_state.dart';
import 'package:sync47_android/services/android_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Renders onboarding screen when not paired', (tester) async {
    const channel = MethodChannel('com.sync47.app/bridge');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPairingInfo':
          return {'isPaired': false};
        case 'getConnectionStatus':
          return 'disconnected';
        case 'getHistory':
          return [];
        default:
          return null;
      }
    });

    final bridge = AndroidBridge();
    final appState = AndroidAppState(bridge: bridge);
    await appState.init();

    await tester.pumpWidget(Sync47AndroidApp(appState: appState));
    await tester.pump();

    expect(find.text('Welcome to Sync47'), findsOneWidget);
    expect(find.text('Scan PC QR Code'), findsOneWidget);
  });
}
