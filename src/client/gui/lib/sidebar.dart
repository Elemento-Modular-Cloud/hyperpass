import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'appearance_settings.dart';
import 'auth/auth_provider.dart';
import 'auth/auth_state.dart';
import 'auth/feature_access.dart';
import 'auth/feature_lock.dart';
import 'brand.dart';
import 'cache/cache_screen.dart';
import 'catalogue/catalogue.dart';
import 'cloud_init/cloud_init_screen.dart';
import 'glass_panel.dart';
import 'help.dart';
import 'l10n/app_localizations.dart';
import 'llm/catalogue/llm_catalogue_screen.dart';
import 'llm/credentials/llm_credentials_screen.dart';
import 'llm/instances/llm_downloaded_screen.dart';
import 'llm/instances/llm_instances_screen.dart';
import 'llm/llm_id.dart';
import 'llm/providers.dart';
import 'llm/setup/llm_setup_screen.dart';
import 'multipass_auth_banner.dart';
import 'overview/overview_screen.dart';
import 'providers.dart';
import 'services/service_bindings.dart';
import 'services/service_instance_id.dart';
import 'services/service_instances_screen.dart';
import 'services/services_screen.dart';
import 'settings/settings.dart';
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
    ref.listen(loadedLlmIdsProvider, (_, ids) {
      final llmId = parseSidebarLlmKey(state);
      if (llmId != null &&
          !ids.any((id) => id.instanceId == llmId.instanceId)) {
        ref.invalidateSelf();
      }
    });
    ref.listen(serviceInstanceIdsProvider, (_, ids) {
      final name = parseServiceInstanceSidebarKey(state);
      if (name != null && !ids.any((id) => id.name == name)) {
        ref.invalidateSelf();
      }
    });

    return OverviewScreen.sidebarKey;
  }

  void set(String key) {
    if (key.sidebarVmId != null) {
      ref.read(vmVisitedProvider(key).notifier).setVisited();
    }
    if (parseSidebarLlmKey(key) != null) {
      ref.read(llmVisitedProvider(key).notifier).setVisited();
    }
    if (parseServiceInstanceSidebarKey(key) != null) {
      ref.read(serviceInstanceVisitedProvider(key).notifier).setVisited();
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

class LlmVisitedNotifier extends Notifier<bool> {
  LlmVisitedNotifier(this.arg);
  final String arg;

  @override
  bool build() => false;

  void setVisited() {
    state = true;
  }
}

final llmVisitedProvider =
    NotifierProvider.family<LlmVisitedNotifier, bool, String>(
  LlmVisitedNotifier.new,
);

class ServiceInstanceVisitedNotifier extends Notifier<bool> {
  ServiceInstanceVisitedNotifier(this.arg);
  final String arg;

  @override
  bool build() => false;

  void setVisited() {
    state = true;
  }
}

final serviceInstanceVisitedProvider =
    NotifierProvider.family<ServiceInstanceVisitedNotifier, bool, String>(
  ServiceInstanceVisitedNotifier.new,
);

/// Electros `navigation-item` / `nav-bar` tokens.
abstract final class _SidebarStyle {
  static const iconColumnWidth = 32.0;
  static const itemHeight = 40.0;
  static const subItemHeight = 32.0;
  static const labelSize = 13.0;
  static const subLabelSize = 12.0;
  static const iconSize = 14.0;
  static const brandAreaHeight = 48.0;
  static const brandLogoSize = 32.0;
  static const brandTitleSize = 15.0;
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

  static Color sectionColor(AppearanceTheme theme) =>
      foreground(theme).withAlpha(140);
}

class SidebarSectionHeader extends ConsumerWidget {
  final String label;
  final bool locked;

  const SidebarSectionHeader(
    this.label, {
    this.locked = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearanceTheme = ref.watch(
      appearanceSettingsProvider.select((settings) => settings.theme),
    );
    final color = _SidebarStyle.sectionColor(appearanceTheme);
    return Opacity(
      opacity: locked ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontFamily: Brand.fontFamily,
                  fontSize: _SidebarStyle.subLabelSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (locked)
              Icon(
                Icons.lock_outline,
                size: 12,
                color: color,
              ),
          ],
        ),
      ),
    );
  }
}

class SideBar extends ConsumerWidget {
  static const animationDuration = Duration(milliseconds: 200);
  static const titleBarHeight = 36.0;
  static const width = 200.0;
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
    final loadedCount = ref.watch(loadedLlmIdsProvider).length;
    final serviceCount = ref.watch(serviceInstanceIdsProvider).length;
    // Rediscover service instances whose daemon tag was lost.
    ref.watch(serviceInstanceSyncProvider);
    final daemonUp = ref.watch(daemonAvailableProvider);
    final multipassStatus = ref.watch(multipassSidebarStatusProvider);
    final access = ref.watch(featureAccessProvider);
    final fg = _SidebarStyle.foreground(appearanceTheme);

    bool isSelected(String key) => key == selectedSidebarKey;

    bool isLlmInstancesSelected() =>
        isSelected(LlmInstancesScreen.sidebarKey) ||
        parseSidebarLlmKey(selectedSidebarKey) != null;

    bool isServiceInstancesSelected() =>
        isSelected(ServiceInstancesScreen.sidebarKey) ||
        parseServiceInstanceSidebarKey(selectedSidebarKey) != null;

    final overview = SidebarEntry(
      icon: FontAwesomeIcons.house,
      selected: isSelected(OverviewScreen.sidebarKey),
      label: l10n.overviewLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(OverviewScreen.sidebarKey);
      },
    );

    final catalogue = SidebarEntry(
      icon: FontAwesomeIcons.layerGroup,
      selected: isSelected(CatalogueScreen.sidebarKey),
      label: l10n.sidebarImagesLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(CatalogueScreen.sidebarKey);
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

    void openOrPromptLocked(bool allowed, String key) {
      if (allowed) {
        ref.read(sidebarKeyNotifier).set(key);
      } else {
        promptFeatureLocked(context, ref);
      }
    }

    final llmCatalogue = SidebarEntry(
      icon: FontAwesomeIcons.book,
      selected: isSelected(LlmCatalogueScreen.sidebarKey),
      label: l10n.sidebarModelsLabel,
      locked: !access.canUseLlms,
      onPressed: () =>
          openOrPromptLocked(access.canUseLlms, LlmCatalogueScreen.sidebarKey),
    );

    final llmInstances = SidebarEntry(
      icon: FontAwesomeIcons.microchip,
      selected: isLlmInstancesSelected(),
      label: l10n.sidebarRuntimeLabel,
      badge: loadedCount.toString(),
      locked: !access.canUseLlms,
      onPressed: () =>
          openOrPromptLocked(access.canUseLlms, LlmInstancesScreen.sidebarKey),
    );

    final activeDownloads = ref
        .watch(modelDownloadQueueProvider)
        .where((j) =>
            j.status == ModelJobStatus.queued ||
            j.status == ModelJobStatus.running)
        .length;

    final llmDownloaded = SidebarEntry(
      icon: FontAwesomeIcons.download,
      selected: isSelected(LlmDownloadedScreen.sidebarKey),
      label: l10n.llmDownloadedLabel,
      badge: access.canUseLlms && activeDownloads > 0
          ? activeDownloads.toString()
          : null,
      locked: !access.canUseLlms,
      onPressed: () => openOrPromptLocked(
          access.canUseLlms, LlmDownloadedScreen.sidebarKey),
    );

    final apiKeyCount = access.canUseLlms
        ? ref.watch(apiKeysProvider).maybeWhen(
              data: (reply) => reply.keys.length,
              orElse: () => 0,
            )
        : 0;

    final llmCredentials = SidebarEntry(
      icon: FontAwesomeIcons.key,
      selected: isSelected(LlmCredentialsScreen.sidebarKey),
      label: l10n.llmCredentialsLabel,
      badge: apiKeyCount.toString(),
      locked: !access.canUseLlms,
      onPressed: () => openOrPromptLocked(
          access.canUseLlms, LlmCredentialsScreen.sidebarKey),
    );

    final missingInstallers = access.canUseLlms
        ? ref.watch(llmBackendsProvider).maybeWhen(
              data: (reply) => reply.backends
                  .where((b) =>
                      (b.id == 'llmfit' || b.id == 'llamacpp') &&
                      b.status != 'ready')
                  .length,
              orElse: () => 0,
            )
        : 0;

    final llmSetup = SidebarEntry(
      icon: FontAwesomeIcons.gears,
      selected: isSelected(LlmSetupScreen.sidebarKey),
      label: l10n.sidebarInstallersLabel,
      badge: missingInstallers > 0 ? missingInstallers.toString() : null,
      locked: !access.canUseLlms,
      onPressed: () =>
          openOrPromptLocked(access.canUseLlms, LlmSetupScreen.sidebarKey),
    );

    final services = SidebarEntry(
      icon: FontAwesomeIcons.cubes,
      selected: isSelected(ServicesScreen.sidebarKey),
      label: l10n.sidebarServiceCatalogueLabel,
      locked: !access.canUseServices,
      onPressed: () =>
          openOrPromptLocked(access.canUseServices, ServicesScreen.sidebarKey),
    );

    final serviceInstances = SidebarEntry(
      icon: FontAwesomeIcons.screwdriverWrench,
      selected: isServiceInstancesSelected(),
      label: l10n.sidebarDeploymentsLabel,
      badge: serviceCount.toString(),
      locked: !access.canUseServices,
      onPressed: () => openOrPromptLocked(
          access.canUseServices, ServiceInstancesScreen.sidebarKey),
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
      label: l10n.sidebarStorageLabel,
      onPressed: () {
        ref.read(sidebarKeyNotifier).set(CacheScreen.sidebarKey);
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BrandAppName(
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
        overview,
        SidebarSectionHeader(l10n.sidebarSectionCompute),
        catalogue,
        instances,
        cloudInit,
        SidebarSectionHeader(
          l10n.sidebarSectionAi,
          locked: !access.canUseLlms,
        ),
        llmCatalogue,
        llmDownloaded,
        llmInstances,
        llmCredentials,
        SidebarSectionHeader(
          l10n.sidebarSectionServices,
          locked: !access.canUseServices,
        ),
        services,
        serviceInstances,
        SidebarSectionHeader(l10n.sidebarSectionManage),
        llmSetup,
        cache,
        help,
        const Spacer(),
        Divider(color: fg.withAlpha(40), height: 1),
        const SizedBox(height: 4),
        _SidebarAccountBadge(
          selected: isSelected(SettingsScreen.sidebarKey),
          onOpenSettings: () {
            ref.read(sidebarKeyNotifier).set(SettingsScreen.sidebarKey);
          },
        ),
        _SidebarSystemSection(
          daemonUp: daemonUp,
          multipassStatus: multipassStatus,
          daemonStatus: daemonStatus,
          multipassStatusRow: multipassStatusRow,
        ),
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

String _accountInitials(String email) {
  final local = email.split('@').first.trim();
  if (local.isEmpty) return '?';
  final parts = local.split(RegExp(r'[._\-]+')).where((p) => p.isNotEmpty);
  if (parts.length >= 2) {
    final a = parts.elementAt(0);
    final b = parts.elementAt(1);
    return ('${a[0]}${b[0]}').toUpperCase();
  }
  return local.substring(0, local.length >= 2 ? 2 : 1).toUpperCase();
}

Uri _gravatarUri(String email, {int size = 112}) {
  final normalized = email.trim().toLowerCase();
  final hash = md5.convert(utf8.encode(normalized)).toString();
  return Uri.https('www.gravatar.com', '/avatar/$hash', {
    's': '$size',
    'd': 'identicon',
    'r': 'g',
  });
}

class _SidebarAccountBadge extends ConsumerWidget {
  const _SidebarAccountBadge({
    required this.onOpenSettings,
    this.selected = false,
  });

  final VoidCallback onOpenSettings;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final appearanceTheme = ref.watch(
      appearanceSettingsProvider.select((settings) => settings.theme),
    );
    final fg = selected
        ? _SidebarStyle.activeFg(appearanceTheme)
        : _SidebarStyle.foreground(appearanceTheme);
    final isDarkTheme = appearanceTheme != AppearanceTheme.light;

    if (auth is AuthGuest) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Material(
          color: selected
              ? _SidebarStyle.activeBg(appearanceTheme)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.radius),
          child: InkWell(
            onTap: onOpenSettings,
            hoverColor: isDarkTheme ? Colors.white10 : Colors.black12,
            borderRadius: BorderRadius.circular(Brand.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Brand.accent.withValues(alpha: 0.25),
                    child: const Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Brand.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.sidebarGuestHeading,
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: fg.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.sidebarGuestSignIn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: Brand.fontFamily,
                            fontSize: _SidebarStyle.statusSize,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.login,
                    size: 16,
                    color: fg.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (auth is! AuthAuthenticated) return const SizedBox.shrink();

    final email = auth.username;
    final initials = _accountInitials(email);
    final gravatar = _gravatarUri(email);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Material(
        color: selected
            ? _SidebarStyle.activeBg(appearanceTheme)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: InkWell(
          onTap: onOpenSettings,
          hoverColor: isDarkTheme ? Colors.white10 : Colors.black12,
          borderRadius: BorderRadius.circular(Brand.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                ClipOval(
                  child: Image.network(
                    gravatar.toString(),
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => CircleAvatar(
                      radius: 14,
                      backgroundColor: Brand.accent.withValues(alpha: 0.25),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Brand.accent,
                          fontFamily: Brand.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return CircleAvatar(
                        radius: 14,
                        backgroundColor: Brand.accent.withValues(alpha: 0.25),
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Brand.accent,
                            fontFamily: Brand.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.sidebarAccountHeading,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: fg.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: Brand.fontFamily,
                          fontSize: _SidebarStyle.statusSize,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: fg.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSystemSection extends ConsumerStatefulWidget {
  const _SidebarSystemSection({
    required this.daemonUp,
    required this.multipassStatus,
    required this.daemonStatus,
    required this.multipassStatusRow,
  });

  final bool daemonUp;
  final MultipassSidebarStatus multipassStatus;
  final Widget daemonStatus;
  final Widget multipassStatusRow;

  @override
  ConsumerState<_SidebarSystemSection> createState() =>
      _SidebarSystemSectionState();
}

class _SidebarSystemSectionState extends ConsumerState<_SidebarSystemSection> {
  var _expanded = false;

  bool get _healthy =>
      widget.daemonUp &&
      (widget.multipassStatus == MultipassSidebarStatus.online ||
          widget.multipassStatus == MultipassSidebarStatus.hidden ||
          widget.multipassStatus == MultipassSidebarStatus.disabled);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appearanceTheme = ref.watch(
      appearanceSettingsProvider.select((settings) => settings.theme),
    );
    final fg = _SidebarStyle.foreground(appearanceTheme);
    final isDarkTheme = appearanceTheme != AppearanceTheme.light;
    final summary =
        _healthy ? l10n.overviewSystemsHealthy : l10n.sidebarSystemAttention;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              hoverColor: isDarkTheme ? Colors.white10 : Colors.black12,
              borderRadius: BorderRadius.circular(Brand.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: _healthy ? Brand.green : Brand.yellow,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.sidebarSystemHeading,
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: fg.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: Brand.fontFamily,
                              fontSize: 11,
                              color: fg.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: fg.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                children: [
                  widget.daemonStatus,
                  widget.multipassStatusRow,
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
            sizeCurve: Curves.easeOut,
          ),
        ],
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
  final bool locked;
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
    this.locked = false,
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
    final fg = selected && !locked ? activeFg : idleFg;
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

    return Opacity(
      opacity: locked ? 0.42 : 1,
      child: Material(
        color: selected && !locked ? activeBg : Colors.transparent,
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
                  if (locked)
                    Icon(
                      Icons.lock_outline,
                      size: 12,
                      color: fg.withValues(alpha: 0.8),
                    )
                  else if (badge != null)
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
      ),
    );
  }
}
