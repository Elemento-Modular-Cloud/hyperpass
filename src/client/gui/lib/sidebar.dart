import 'dart:async';

import 'package:basics/basics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import 'catalogue/catalogue.dart';
import 'brand.dart';
import 'cache/cache_screen.dart';
import 'distro_branding.dart';
import 'extensions.dart';
import 'help.dart';
import 'l10n/app_localizations.dart';
import 'platform/platform.dart';
import 'providers.dart';
import 'settings/settings.dart';
import 'vm_details/terminal.dart';
import 'vm_table/vm_table_screen.dart';

extension on String {
  String? get sidebarVmName => startsWith('vm-') ? withoutPrefix('vm-') : null;
}

class SidebarKeyNotifier extends Notifier<String> {
  @override
  String build() {
    ref.listen(vmNamesProvider, (_, names) {
      final vmName = state.sidebarVmName;
      if (vmName != null && !names.contains(vmName)) ref.invalidateSelf();
    });

    return CatalogueScreen.sidebarKey;
  }

  void set(String key) {
    if (key.sidebarVmName != null) {
      ref.read(vmVisitedProvider(key).notifier).setVisited();
    }
    state = key;
  }
}

final sidebarKeyProvider = NotifierProvider<SidebarKeyNotifier, String>(
  SidebarKeyNotifier.new,
);

class VmVisitedNotifier extends Notifier<bool> {
  VmVisitedNotifier(this.arg);
  final String arg;

  @override
  bool build() {
    return false;
  }

  void setVisited() {
    state = true;
  }
}

final vmVisitedProvider =
    NotifierProvider.family<VmVisitedNotifier, bool, String>(
  VmVisitedNotifier.new,
);

class SidebarExpandedNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void setExpanded(bool value) {
    state = value;
  }
}

final sidebarExpandedProvider = NotifierProvider<SidebarExpandedNotifier, bool>(
  SidebarExpandedNotifier.new,
);

class SidebarPushContentNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  void setPushContent(bool value) {
    state = value;
  }
}

final sidebarPushContentProvider =
    NotifierProvider<SidebarPushContentNotifier, bool>(
  SidebarPushContentNotifier.new,
);
Timer? sidebarExpandTimer;

class SideBar extends ConsumerWidget {
  static const animationDuration = Duration(milliseconds: 200);

  /// Reserved height for the borderless window title strip.
  static const titleBarHeight = 36.0;

  static double get collapsedWidth => mpPlatform.sidebarCollapsedWidth;
  static const expandedWidth = 240.0;

  const SideBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selectedSidebarKey = ref.watch(sidebarKeyProvider);
    final sidebarKeyNotifier = sidebarKeyProvider.notifier;
    final vmNames = ref.watch(vmNamesProvider);
    final expanded = ref.watch(sidebarExpandedProvider);
    final pushContent = ref.watch(sidebarPushContentProvider);

    bool isSelected(String key) => key == selectedSidebarKey;

    final catalogue = SidebarEntry(
      icon: SvgPicture.asset('assets/catalogue.svg'),
      selected: isSelected(CatalogueScreen.sidebarKey),
      label: l10n.catalogueLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(CatalogueScreen.sidebarKey);
      },
    );

    final instances = SidebarEntry(
      icon: SvgPicture.asset('assets/instances.svg'),
      selected: isSelected(VmTableScreen.sidebarKey) ||
          !expanded && selectedSidebarKey.startsWith('vm-'),
      label: l10n.sidebarInstances,
      badge: vmNames.length.toString(),
      onPressed: () {
        ref.read(sidebarKeyProvider.notifier).set(VmTableScreen.sidebarKey);
      },
    );

    final help = SidebarEntry(
      icon: SvgPicture.asset('assets/help.svg'),
      selected: isSelected(HelpScreen.sidebarKey),
      label: l10n.helpLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(HelpScreen.sidebarKey);
      },
    );

    final cache = SidebarEntry(
      icon: SvgPicture.asset('assets/cache.svg'),
      selected: isSelected(CacheScreen.sidebarKey),
      label: l10n.cacheLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(CacheScreen.sidebarKey);
      },
    );

    final settings = SidebarEntry(
      icon: SvgPicture.asset('assets/settings.svg'),
      selected: isSelected(SettingsScreen.sidebarKey),
      label: l10n.settingsLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(SettingsScreen.sidebarKey);
      },
    );

    final pinSidebarButton = Material(
      color: Colors.transparent,
      child: IconButton(
        hoverColor: Colors.white24,
        splashRadius: 16,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        icon: Icon(
          pushContent ? Icons.chevron_left : Icons.chevron_right,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () => ref
            .read(sidebarPushContentProvider.notifier)
            .setPushContent(!pushContent),
      ),
    );

    final logo = SvgPicture.asset(
      Brand.logoAsset,
      width: 26,
      height: 26,
      colorFilter: const ColorFilter.mode(
        Brand.yellow,
        BlendMode.srcIn,
      ),
    );

    final brandText = DefaultTextStyle.merge(
      style: const TextStyle(height: 1.2),
      child: Text.rich(
        [
          '${Brand.companyName}\n'
              .span
              .size(10)
              .color(Brand.greyBody),
          Brand.appName.span.size(17).color(Brand.crystalWhite).bold,
        ].spans,
      ),
    );

    // Fixed height so expanding/collapsing only fades chrome — nav items stay put.
    // Logo centers when collapsed; text/pin overlay without shifting layout.
    final header = DragToMoveArea(
      child: Padding(
        // Clear the fake title bar; sidebar chrome itself still paints to y=0.
        padding: const EdgeInsets.only(
          top: SideBar.titleBarHeight,
          bottom: 12,
        ),
        child: SizedBox(
          height: 40,
          child: Stack(
            children: [
              AnimatedAlign(
                duration: SideBar.animationDuration,
                alignment:
                    expanded ? Alignment.centerLeft : Alignment.center,
                child: logo,
              ),
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: expanded ? 1 : 0,
                  duration: SideBar.animationDuration,
                  child: IgnorePointer(
                    ignoring: !expanded,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 38), // logo (26) + gap (12)
                        Expanded(child: brandText),
                        const SizedBox(width: 4),
                        pinSidebarButton,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final vmEntries = vmNames.map((name) {
      final key = 'vm-$name';
      final hasShells = ref.watch(
        runningShellsProvider(name).select((n) => n > 0),
      );
      final os = ref.watch(
        vmInfoProvider(name).select((i) => i.instanceInfo.os),
      );
      final accent = distroBranding(os).accent;
      return SidebarEntry(
        key: ValueKey(key),
        icon: Opacity(
          opacity: hasShells ? 1 : 0.35,
          child: SvgPicture.asset(
            'assets/shell.svg',
            width: 15,
            height: 15,
            colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
          ),
        ),
        selected: isSelected(key) && expanded,
        label: name,
        onPressed: () {
          ref.read(sidebarKeyNotifier).set(key);
        },
      );
    });

    final sidebar = MouseRegion(
      onEnter: (_) {
        if (pushContent) return;
        sidebarExpandTimer?.cancel();
        sidebarExpandTimer = Timer(const Duration(milliseconds: 200), () {
          ref.read(sidebarExpandedProvider.notifier).setExpanded(true);
        });
      },
      onExit: (_) {
        if (pushContent) return;
        sidebarExpandTimer?.cancel();
        ref.read(sidebarExpandedProvider.notifier).setExpanded(false);
      },
      child: AnimatedContainer(
        duration: SideBar.animationDuration,
        color: Brand.voidBlack,
        padding: EdgeInsets.fromLTRB(expanded ? 12 : 6, 0, expanded ? 12 : 6, 12),
        width: expanded ? expandedWidth : collapsedWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            catalogue,
            instances,
            Expanded(child: ListView(children: vmEntries.toList())),
            Divider(color: Colors.white.withAlpha(77)),
            cache,
            help,
            settings,
          ],
        ),
      ),
    );

    return DefaultTextStyle(
      softWrap: false,
      style: const TextStyle(
        height: 1,
        overflow: TextOverflow.clip,
        color: Brand.crystalWhite,
        fontWeight: FontWeight.w300,
      ),
      child: sidebar,
    );
  }
}

class SidebarEntry extends ConsumerWidget {
  final String label;
  final Widget icon;
  final String? badge;
  final VoidCallback onPressed;
  final bool selected;

  const SidebarEntry({
    super.key,
    required this.label,
    required this.icon,
    this.badge,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(sidebarExpandedProvider);

    final iconChild = badge == null
        ? icon
        : Badge(
            backgroundColor: const Color(0xff333333),
            isLabelVisible: !expanded,
            label: Text(
              badge!,
              style: const TextStyle(color: Brand.crystalWhite),
            ),
            offset: const Offset(10, -6),
            child: icon,
          );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          left: selected
              ? const BorderSide(color: Colors.white, width: 2)
              : BorderSide.none,
        ),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(
            vertical: 18,
            horizontal: expanded ? 12 : 0,
          ),
          backgroundColor:
              selected ? const Color(0xff2A2A32) : Colors.transparent,
          foregroundColor: selected ? Brand.yellow : Brand.crystalWhite,
          disabledForegroundColor: Brand.crystalWhite.withAlpha(128),
        ),
        child: expanded
            ? Row(
                children: [
                  iconChild,
                  Expanded(
                    flex: 5,
                    child: Text(
                      '    $label',
                      softWrap: false,
                      style: TextStyle(
                        color: selected ? Brand.yellow : Brand.crystalWhite,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Flexible(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xff333333),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badge!,
                          softWrap: false,
                          style: const TextStyle(color: Brand.crystalWhite),
                        ),
                      ),
                    ),
                ],
              )
            : Center(child: iconChild),
      ),
    );
  }
}
