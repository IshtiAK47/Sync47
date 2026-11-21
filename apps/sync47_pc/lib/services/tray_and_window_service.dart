import 'dart:io';
import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'app_state.dart';

class TrayAndWindowService with TrayListener, WindowListener {
  final AppState appState;
  final bool isBootMinimized;
  final VoidCallback onOpenPairingRequested;

  TrayAndWindowService({
    required this.appState,
    required this.isBootMinimized,
    required this.onOpenPairingRequested,
  });

  Future<void> init() async {
    // 1. Initialize Window Manager
    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    const windowOptions = WindowOptions(
      size: Size(380, 540),
      minimumSize: Size(360, 500),
      maximumSize: Size(420, 650),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'Sync47',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
      if (isBootMinimized || appState.startMinimized) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

    // 2. Initialize Launch at Startup
    try {
      launchAtStartup.setup(
        appName: 'Sync47',
        appPath: Platform.resolvedExecutable,
        args: ['--minimized'],
      );
    } catch (e) {
      debugPrint('[TrayAndWindowService] Error setting up launchAtStartup: $e');
    }

    // 3. Initialize Tray Manager
    try {
      trayManager.addListener(this);
      await _updateTrayIcon();
      await updateTrayMenu();
    } catch (e) {
      debugPrint('[TrayAndWindowService] Error initializing trayManager: $e');
    }
  }

  Future<void> _updateTrayIcon() async {
    if (Platform.isWindows) {
      await trayManager.setIcon('assets/app_icon.ico');
    } else {
      await trayManager.setIcon('assets/tray_icon.png');
    }
    await trayManager.setToolTip('Sync47 - Local Wi-Fi Clipboard');
  }

  Future<void> updateTrayMenu() async {
    String statusText;
    switch (appState.connectionStatus) {
      case ConnectionStatus.connected:
        statusText = '● Connected: ${appState.connectedDeviceName ?? "Phone"}';
        break;
      case ConnectionStatus.waiting:
        statusText = '○ Waiting for Phone (Wi-Fi)';
        break;
      case ConnectionStatus.paused:
        statusText = '⏸ Sync Paused';
        break;
    }

    final menu = Menu(
      items: [
        MenuItem(
          key: 'status',
          label: statusText,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'copy_last',
          label: 'Copy Last Clip',
          disabled: appState.history.isEmpty,
        ),
        MenuItem(
          key: 'pause_resume',
          label: appState.isPaused ? 'Resume Sync' : 'Pause Sync',
        ),
        MenuItem(
          key: 'pair',
          label: 'Pair Phone...',
        ),
        MenuItem.separator(),
        MenuItem.checkbox(
          key: 'autostart',
          label: 'Launch on Startup',
          checked: appState.launchAtStartup,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit Sync47',
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    await updateTrayMenu();
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'copy_last':
        if (appState.history.isNotEmpty) {
          await appState.copyClip(appState.history.first);
        }
        break;
      case 'pause_resume':
        await appState.togglePause();
        await updateTrayMenu();
        break;
      case 'pair':
        await windowManager.show();
        await windowManager.focus();
        onOpenPairingRequested();
        break;
      case 'autostart':
        final newValue = !appState.launchAtStartup;
        await appState.setLaunchAtStartup(newValue);
        if (newValue) {
          await launchAtStartup.enable();
        } else {
          await launchAtStartup.disable();
        }
        await updateTrayMenu();
        break;
      case 'quit':
        await windowManager.setPreventClose(false);
        await windowManager.close();
        exit(0);
    }
  }

  @override
  void onWindowClose() async {
    // Prevent app quit on close, minimize to system tray instead
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
