import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'before_quit_dialog.dart';
import 'brand.dart';
import 'app_background.dart';
import 'app_theme.dart';
import 'appearance_settings.dart';
import 'l10n/app_localizations.dart';
import 'cache/cache_screen.dart';
import 'catalogue/catalogue.dart';
import 'cloud_init/cloud_init_screen.dart';
import 'daemon_unavailable.dart';
import 'help.dart';
import 'logger.dart';
import 'models/models_screen.dart';
import 'multipass_auth_banner.dart';
import 'notifications.dart';
import 'platform/platform.dart';
import 'providers.dart';
import 'settings/hotkey.dart';
import 'settings/settings.dart';
import 'sidebar.dart';
import 'tray_menu.dart';
import 'update_available.dart';
import 'vm_details/vm_details.dart';
import 'vm_table/vm_table_screen.dart';
import 'window_size.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await setupLogger();

  await localNotifier.setup(
    appName: Brand.appName,
    shortcutPolicy: ShortcutPolicy.requireCreate, // Only for Windows
  );

  final sharedPreferences = await SharedPreferences.getInstance();
  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    center: true,
    minimumSize: const Size(750, 450),
    size: await deriveWindowSize(sharedPreferences),
    title: Brand.appName,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await hotKeyManager.unregisterAll();

  providerContainer = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
    ],
  );
  setupTrayMenu(providerContainer);
  runApp(
    UncontrolledProviderScope(
      container: providerContainer,
      child: const HyperpassApp(),
    ),
  );
}

class HyperpassApp extends ConsumerWidget {
  const HyperpassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    return MaterialApp(
      theme: buildAppTheme(appearance),
      home: const UpdateSystemNotificationListener(child: App()),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WindowListener {
  @override
  Widget build(BuildContext context) {
    final currentKey = ref.watch(sidebarKeyProvider);
    final vms = ref.watch(vmIdsProvider);

    final widgets = {
      CatalogueScreen.sidebarKey: const CatalogueScreen(),
      VmTableScreen.sidebarKey: const VmTableScreen(),
      ModelsScreen.sidebarKey: const ModelsScreen(),
      CacheScreen.sidebarKey: const CacheScreen(),
      CloudInitScreen.sidebarKey: const CloudInitScreen(),
      SettingsScreen.sidebarKey: const SettingsScreen(),
      HelpScreen.sidebarKey: const HelpScreen(),
      for (final id in vms) id.sidebarKey: VmDetailsScreen(id),
    };

    final content = Stack(
      fit: StackFit.expand,
      children: widgets.entries.map((e) {
        final MapEntry(:key, value: widget) = e;
        final isCurrent = key == currentKey;
        var maintainState = key != SettingsScreen.sidebarKey;
        if (key.startsWith('vm-')) {
          maintainState = ref.read(vmVisitedProvider(key));
        }
        return Visibility(
          key: Key(key),
          maintainState: maintainState,
          visible: isCurrent,
          child: FocusScope(
            autofocus: isCurrent,
            canRequestFocus: isCurrent,
            skipTraversal: !isCurrent,
            child: widget,
          ),
        );
      }).toList(),
    );

    final hotkey = ref.watch(hotkeyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Brand.accent : Brand.voidBlack;
    final sidebarWidth = SideBar.totalWidth;

    return Stack(
      children: [
        const Positioned.fill(child: AppBackground()),
        Positioned(
          bottom: 0,
          right: 0,
          top: 0,
          left: sidebarWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: SideBar.titleBarHeight),
            child: content,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          bottom: 0,
          child: CallbackGlobalShortcuts(
            key: hotkey != null ? GlobalObjectKey(hotkey) : null,
            bindings: {if (hotkey != null) hotkey: goToPrimary},
            child: const SideBar(),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: mpPlatform.showWindowCaptionButtons ? 138 : 0,
          height: SideBar.titleBarHeight,
          child: DragToMoveArea(
            child: Center(
              child: Text(
                Brand.appName,
                style: TextStyle(
                  color: titleColor,
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                  fontFamily: Brand.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
        if (mpPlatform.showWindowCaptionButtons)
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 138,
              height: kWindowCaptionHeight,
              child: WindowCaption(
                backgroundColor: Colors.transparent,
                brightness: isDark ? Brightness.dark : Brightness.light,
              ),
            ),
          ),
        const Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(width: 400, child: NotificationList()),
        ),
        const DaemonUnavailable(),
        Positioned(
          left: sidebarWidth,
          right: 0,
          top: SideBar.titleBarHeight,
          child: const MultipassAuthBanner(),
        ),
      ],
    );
  }

  void goToPrimary() {
    final vms = ref.read(vmIdsProvider);
    final primary = ref.read(clientSettingProvider(primaryNameKey));
    final primaryId = hyperpassVm(primary);
    if (vms.contains(primaryId)) {
      ref.read(sidebarKeyProvider.notifier).set(primaryId.sidebarKey);
      windowManager.showAndRestore();
    }
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // this event handler is called continuously during a window resizing operation
  // so we want to save the data to the disk only after the resizing stops
  @override
  void onWindowResize() => saveWindowSizeTimer.reset();

  @override
  void onWindowClose() async {
    if (!await windowManager.isPreventClose()) return;
    final daemonAvailable = ref.read(daemonAvailableProvider);
    final vmsRunning =
        ref.read(vmStatusesProvider).values.contains(Status.RUNNING);
    final closeJob = ref.read(guiSettingProvider(onAppCloseKey));

    // nothing to do
    if (!daemonAvailable || !vmsRunning || closeJob == 'nothing') {
      windowManager.destroy();
      return;
    }

    // checking the need to restore the window
    if (!await windowManager.isVisible() || await windowManager.isMinimized()) {
      windowManager.showAndRestore();
    }

    stopAllInstances() {
      final runningVMs = ref
          .read(vmStatusesProvider)
          .entries
          .where((entry) => entry.value == Status.RUNNING)
          .map((entry) => entry.key)
          .toList();
      final notificationsNotifier = ref.read(notificationsProvider.notifier);
      notificationsNotifier.addOperation(
        runManagedAction(
          clientFor: (source) => switch (source) {
            DaemonSource.hyperpass => ref.read(grpcClientProvider),
            DaemonSource.multipass => ref.read(multipassGrpcClientProvider),
          },
          ids: runningVMs,
          action: (client, names) => client.stop(names),
        ),
        loading: 'Stopping all instances',
        onError: (error) => 'Failed to stop all instances: $error',
        onSuccess: (_) {
          windowManager.destroy();
          return 'Stopped all instances';
        },
      );
    }

    if (closeJob == 'ask') {
      // Get running instances count
      final vmInfos = ref.read(vmInfosProvider);
      final runningCount = vmInfos
          .where((info) => info.instanceStatus.status == Status.RUNNING)
          .length;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => BeforeQuitDialog(
          runningCount: runningCount,
          onStop: (remember) {
            ref
                .read(guiSettingProvider(onAppCloseKey).notifier)
                .set(remember ? 'stop' : 'ask');
            stopAllInstances();
            Navigator.pop(context);
          },
          onKeep: (remember) {
            ref
                .read(guiSettingProvider(onAppCloseKey).notifier)
                .set(remember ? 'nothing' : 'ask');
            windowManager.destroy();
          },
        ),
      );
    } else {
      stopAllInstances();
    }
  }
}
