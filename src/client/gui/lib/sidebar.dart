import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'appearance_settings.dart';
import 'brand.dart';
import 'cache/cache_screen.dart';
import 'catalogue/catalogue.dart';
import 'cloud_init/cloud_init_screen.dart';
import 'distro_branding.dart';
import 'glass_panel.dart';
import 'help.dart';
import 'l10n/app_localizations.dart';
import 'multipass_auth_banner.dart';
import 'providers.dart';
import 'settings/settings.dart';
import 'vm_details/terminal.dart';
import 'vm_table/vm_table_screen.dart';

extension on String {
  VmId? get sidebarVmId => parseSidebarVmKey(this);
}

class SidebarKeyNotifier extends Notifier<String> {
  @override
  String build() {
    ref.listen(vmIdsProvider, (_, ids) {
      final vmId = state.sidebarVmId;
      if (vmId != null && !ids.contains(vmId)) ref.invalidateSelf();
    });

    return CatalogueScreen.sidebarKey;
  }

  void set(String key) {
    if (key.sidebarVmId != null) {
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
  bool build() => false;

  void setVisited() {
    state = true;
  }
}

final vmVisitedProvider =
    NotifierProvider.family<VmVisitedNotifier, bool, String>(
  VmVisitedNotifier.new,
);

/// Electros `navigation-item` / `nav-bar` tokens.
abstract final class _SidebarStyle {
  static const iconColumnWidth = 32.0;
  static const itemHeight = 40.0;
  static const subItemHeight = 32.0;
  static const labelSize = 13.0;
  static const subLabelSize = 12.0;
  static const iconSize = 14.0;
  /// Electros `.electrosNavBarLogo` is `5rem` with `1rem` margin — keep compact for two-line title.
  static const brandAreaHeight = 48.0;
  static const brandLogoSize = 32.0;
  static const brandTitleSize = 15.0;
  /// Electros `.electrosNavBarElemento`: `1.5rem` mark / `1.25rem` text.
  static const footerLogoSize = 20.0;
  static const footerSize = 16.0;
  static const statusSize = 12.0;

  static Color foreground(AppearanceTheme theme) => switch (theme) {
        AppearanceTheme.light => Brand.greyDarker,
        AppearanceTheme.dark => Brand.greyBody,
        AppearanceTheme.highContrast => Brand.crystalWhite,
      };

  static Color activeBg(AppearanceTheme theme) => switch (theme) {
        AppearanceTheme.light => Brand.accentLight,
        AppearanceTheme.dark => Brand.black,
        AppearanceTheme.highContrast => Colors.black,
      };

  static Color activeFg(AppearanceTheme theme) => switch (theme) {
        AppearanceTheme.light => Brand.voidBlack,
        AppearanceTheme.dark => Brand.accent,
        AppearanceTheme.highContrast => Brand.accent,
      };

  static Color headerTitleColor(AppearanceTheme theme) => switch (theme) {
        AppearanceTheme.light => Brand.greyDarker,
        AppearanceTheme.dark => Brand.crystalWhite,
        AppearanceTheme.highContrast => Brand.crystalWhite,
      };
}

class SideBar extends ConsumerWidget {
  static const animationDuration = Duration(milliseconds: 200);

  /// Reserved height for the borderless window title strip.
  static const titleBarHeight = 36.0;

  /// Narrower than Electros `240px` so content gets more room.
  static const width = 200.0;

  /// Right gutter matching Electros `nav-bar` `margin-right`.
  static const gutter = 12.0;

  static double get totalWidth => width + gutter;

  const SideBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final appearance = ref.watch(appearanceSettingsProvider);
    final appearanceTheme = appearance.theme;
    final glass = context.glass;
    final selectedSidebarKey = ref.watch(sidebarKeyProvider);
    final sidebarKeyNotifier = sidebarKeyProvider.notifier;
    final vmNames = ref.watch(vmIdsProvider);
    final daemonUp = ref.watch(daemonAvailableProvider);
    final multipassStatus = ref.watch(multipassSidebarStatusProvider);
    final fg = _SidebarStyle.foreground(appearanceTheme);

    bool isSelected(String key) => key == selectedSidebarKey;

    final catalogue = SidebarEntry(
      icon: FontAwesomeIcons.layerGroup,
      selected: isSelected(CatalogueScreen.sidebarKey),
      label: l10n.catalogueLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(CatalogueScreen.sidebarKey);
      },
    );

    final instances = SidebarEntry(
      icon: FontAwesomeIcons.server,
      selected: isSelected(VmTableScreen.sidebarKey) ||
          selectedSidebarKey.startsWith('vm-'),
      label: l10n.sidebarInstances,
      badge: vmNames.length.toString(),
      onPressed: () {
        ref.read(sidebarKeyProvider.notifier).set(VmTableScreen.sidebarKey);
      },
    );

    final help = SidebarEntry(
      icon: FontAwesomeIcons.circleQuestion,
      selected: isSelected(HelpScreen.sidebarKey),
      label: l10n.helpLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(HelpScreen.sidebarKey);
      },
    );

    final cache = SidebarEntry(
      icon: FontAwesomeIcons.boxArchive,
      selected: isSelected(CacheScreen.sidebarKey),
      label: l10n.cacheLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(CacheScreen.sidebarKey);
      },
    );

    final cloudInit = SidebarEntry(
      icon: FontAwesomeIcons.cloud,
      selected: isSelected(CloudInitScreen.sidebarKey),
      label: l10n.cloudInitLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(CloudInitScreen.sidebarKey);
      },
    );

    final settings = SidebarEntry(
      icon: FontAwesomeIcons.gear,
      selected: isSelected(SettingsScreen.sidebarKey),
      label: l10n.settingsLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(SettingsScreen.sidebarKey);
      },
    );

    final header = DragToMoveArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: SizedBox(
          height: _SidebarStyle.brandAreaHeight,
          child: Row(
            children: [
              SvgPicture.asset(
                Brand.logoAsset,
                width: _SidebarStyle.brandLogoSize,
                height: _SidebarStyle.brandLogoSize,
                colorFilter: const ColorFilter.mode(
                  Brand.accent,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  Brand.appName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _SidebarStyle.headerTitleColor(appearanceTheme),
                    fontFamily: Brand.fontFamily,
                    fontSize: _SidebarStyle.brandTitleSize,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final vmEntries = vmNames.map((id) {
      final key = id.sidebarKey;
      final hasShells = ref.watch(
        runningShellsProvider(id).select((n) => n > 0),
      );
      final info = ref.watch(vmInfoProvider(id));
      final branding = distroBranding(
        info.instanceInfo.os,
        release: info.instanceInfo.currentRelease,
      );
      return SidebarEntry(
        key: ValueKey(key),
        icon: FontAwesomeIcons.terminal,
        selected: isSelected(key),
        label: id.source == DaemonSource.multipass
            ? '${id.name} · MP'
            : id.name,
        subroute: true,
        iconOpacity: hasShells ? 1 : 0.35,
        iconColor: branding.accent,
        onPressed: () {
          ref.read(sidebarKeyNotifier).set(key);
        },
      );
    });

    final vmList = vmEntries.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(left: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: appearanceTheme == AppearanceTheme.light
                        ? Brand.greyDarker.withAlpha(80)
                        : Brand.greyBody,
                  ),
                ),
              ),
              child: Column(children: vmEntries.toList()),
            ),
          );

    final daemonStatus = _SidebarStatusRow(
      icon: FontAwesomeIcons.microchip,
      label: l10n.sidebarDaemonService,
      online: daemonUp,
    );

    final multipassStatusRow = _SidebarStatusRow(
      icon: FontAwesomeIcons.cube,
      label: switch (multipassStatus) {
        MultipassSidebarStatus.needsAuth => l10n.sidebarMultipassNeedsAuth,
        MultipassSidebarStatus.disabled => l10n.sidebarMultipassDisabled,
        MultipassSidebarStatus.hidden ||
        MultipassSidebarStatus.online ||
        MultipassSidebarStatus.offline =>
          l10n.sidebarMultipassService,
      },
      online: multipassStatus == MultipassSidebarStatus.online,
      onTap: multipassStatus == MultipassSidebarStatus.needsAuth
          ? () => MultipassAuthBanner.showAuthDialog(context)
          : null,
    );

    final elementoFooter = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => launchUrl(Brand.docsUrl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                Brand.elementoLogoAsset,
                width: _SidebarStyle.footerLogoSize,
                height: _SidebarStyle.footerLogoSize,
                colorFilter: const ColorFilter.mode(
                  Brand.yellow,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                Brand.companyName,
                style: const TextStyle(
                  color: Brand.yellow,
                  fontFamily: Brand.fontFamily,
                  fontSize: _SidebarStyle.footerSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final radius = BorderRadius.only(
      topRight: Radius.circular(Brand.radius),
    );

    final navBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        catalogue,
        cloudInit,
        instances,
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [vmList],
          ),
        ),
        Divider(color: fg.withAlpha(40), height: 1),
        cache,
        help,
        settings,
        const SizedBox(height: 8),
        daemonStatus,
        multipassStatusRow,
        elementoFooter,
      ],
    );

    return DefaultTextStyle(
      softWrap: false,
      style: TextStyle(
        height: 1,
        overflow: TextOverflow.clip,
        color: fg,
        fontFamily: Brand.fontFamily,
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          top: SideBar.titleBarHeight,
          right: SideBar.gutter,
        ),
        child: SizedBox(
          width: SideBar.width,
          child: GlassPanel(
            borderRadius: radius,
            border: Border(
              top: BorderSide(color: glass.border),
              right: BorderSide(color: glass.border),
              bottom: BorderSide.none,
              left: BorderSide.none,
            ),
            child: navBody,
          ),
        ),
      ),
    );
  }
}

class _SidebarStatusRow extends ConsumerWidget {
  const _SidebarStatusRow({
    required this.icon,
    required this.label,
    required this.online,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool online;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearanceTheme = ref.watch(
      appearanceSettingsProvider.select((settings) => settings.theme),
    );
    final fg = _SidebarStyle.foreground(appearanceTheme);
    final dot = online ? Brand.green : Brand.yellow;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          FaIcon(icon, size: 14, color: dot),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontFamily: Brand.fontFamily,
                fontSize: _SidebarStyle.statusSize,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class SidebarEntry extends ConsumerWidget {
  final String label;
  final IconData icon;
  final String? badge;
  final VoidCallback onPressed;
  final bool selected;
  final bool subroute;
  final double iconOpacity;
  final Color? iconColor;

  const SidebarEntry({
    super.key,
    required this.label,
    required this.icon,
    this.badge,
    required this.onPressed,
    this.selected = false,
    this.subroute = false,
    this.iconOpacity = 1,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearanceTheme = ref.watch(
      appearanceSettingsProvider.select((settings) => settings.theme),
    );
    final activeBg = _SidebarStyle.activeBg(appearanceTheme);
    final activeFg = _SidebarStyle.activeFg(appearanceTheme);
    final idleFg = _SidebarStyle.foreground(appearanceTheme);
    final fg = selected ? activeFg : idleFg;
    final height =
        subroute ? _SidebarStyle.subItemHeight : _SidebarStyle.itemHeight;
    final fontSize =
        subroute ? _SidebarStyle.subLabelSize : _SidebarStyle.labelSize;
    final isDarkTheme = appearanceTheme != AppearanceTheme.light;

    final iconChild = Opacity(
      opacity: iconOpacity,
      child: SizedBox(
        width: _SidebarStyle.iconColumnWidth,
        child: Center(
          child: FaIcon(
            icon,
            size: _SidebarStyle.iconSize,
            color: iconColor ?? fg,
          ),
        ),
      ),
    );

    return Material(
      color: selected ? activeBg : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: isDarkTheme ? Colors.white10 : Colors.black12,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.only(
              left: subroute ? 8 : 8,
              right: 8,
            ),
            child: Row(
              children: [
                iconChild,
                Expanded(
                  child: Text(
                    label,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontFamily: Brand.fontFamily,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isDarkTheme
                          ? Brand.black
                          : Brand.greyBody.withAlpha(60),
                      borderRadius: BorderRadius.circular(Brand.radius),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: fg,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
