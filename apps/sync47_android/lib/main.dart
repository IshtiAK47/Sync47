import 'package:flutter/material.dart';
import 'providers/android_app_state.dart';
import 'services/android_bridge.dart';
import 'ui/dashboard_screen.dart';
import 'ui/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bridge = AndroidBridge();
  final appState = AndroidAppState(bridge: bridge);
  await appState.init();

  runApp(Sync47AndroidApp(appState: appState));
}

class Sync47AndroidApp extends StatelessWidget {
  final AndroidAppState appState;

  const Sync47AndroidApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF4F46E5);

    return MaterialApp(
      title: 'Sync47',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.dark,
        ),
      ),
      home: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          if (appState.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: primaryColor)),
            );
          }
          if (appState.isPaired) {
            return DashboardScreen(appState: appState);
          }
          return OnboardingScreen(appState: appState);
        },
      ),
    );
  }
}
