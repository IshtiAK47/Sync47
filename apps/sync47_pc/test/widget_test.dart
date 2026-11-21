import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync47_pc/services/app_state.dart';
import 'package:sync47_pc/services/settings_service.dart';
import 'package:sync47_pc/ui/popover_window.dart';

void main() {
  testWidgets('PopoverWindow renders header and empty state cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsService = SettingsService(prefs);
    final appState = AppState(settingsService: settingsService);

    await tester.pumpWidget(
      MaterialApp(
        home: PopoverWindow(appState: appState),
      ),
    );

    expect(find.text('Sync47'), findsOneWidget);
    expect(find.text('No Synced Clips Yet'), findsOneWidget);
    expect(find.text('Pair Phone'), findsOneWidget);
  });
}
