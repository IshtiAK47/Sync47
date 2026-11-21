import 'package:flutter/material.dart';
import 'services/app_state.dart';
import 'services/settings_service.dart';
import 'services/tray_and_window_service.dart';
import 'ui/popover_window.dart';
import 'ui/qr_pairing_dialog.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final isBootMinimized = args.contains('--minimized') || args.contains('-minimized');

  // Initialize persistent settings
  final settingsService = await SettingsService.init();

  // Initialize centralized state
  final appState = AppState(settingsService: settingsService);
  await appState.init();

  // Global navigator key for opening dialogs triggered from system tray
  final navigatorKey = GlobalKey<NavigatorState>();

  // Initialize System Tray and Window Management
  final trayService = TrayAndWindowService(
    appState: appState,
    isBootMinimized: isBootMinimized,
    onOpenPairingRequested: () {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        showDialog(
          context: ctx,
          builder: (_) => QrPairingDialog(appState: appState),
        );
      }
    },
  );
  await trayService.init();

  runApp(Sync47PcApp(
    appState: appState,
    navigatorKey: navigatorKey,
  ));
}

class Sync47PcApp extends StatelessWidget {
  final AppState appState;
  final GlobalKey<NavigatorState> navigatorKey;

  const Sync47PcApp({
    super.key,
    required this.appState,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF4F46E5);

    return MaterialApp(
      title: 'Sync47',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ),
        fontFamily: 'Segoe UI',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: PopoverWindow(appState: appState),
    );
  }
}
