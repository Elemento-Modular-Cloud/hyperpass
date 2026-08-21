import 'dart:io';

import 'package:flutter/widgets.dart';

import '../settings/autostart_notifiers.dart';
import 'linux.dart';
import 'macos.dart';
import 'windows.dart';

abstract class MpPlatform {
  String get ffiLibraryName;

  AutostartNotifier autostartNotifier();

  Map<String, String> get drivers;

  String get trayIconFile;

  Map<SingleActivator, Intent> get terminalShortcuts;

  bool get showLocalUpdateNotifications;

  bool get showToggleWindow;

  String get altKey => 'Alt';

  String get metaKey => 'Meta';

  String? get homeDirectory;

  /// Padding above sidebar brand lockup (traffic lights live in the title bar).
  double get windowTopInset => 8;

  /// Collapsed sidebar width.
  double get sidebarCollapsedWidth => 60;

  /// Windows needs in-app caption buttons when the native title bar is hidden.
  bool get showWindowCaptionButtons => false;
}

MpPlatform _getPlatform() {
  if (Platform.isLinux) return LinuxPlatform();
  if (Platform.isMacOS) return MacOSPlatform();
  if (Platform.isWindows) return WindowsPlatform();
  throw UnimplementedError('Platform not supported');
}

final mpPlatform = _getPlatform();
