import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../auth/feature_access.dart';
import '../brand.dart';
import '../catalogue/catalogue.dart';
import '../catalogue/catalogue_surface.dart';
import '../l10n/app_localizations.dart';
import '../llm/catalogue/llm_catalogue_screen.dart';
import '../llm/instances/llm_downloaded_screen.dart';
import '../llm/instances/llm_instances_screen.dart';
import '../services/service_instances_screen.dart';
import '../services/services_screen.dart';
import '../sidebar.dart';
import '../vm_table/vm_table_screen.dart';

class OverviewFeatureBanners extends ConsumerWidget {
  const OverviewFeatureBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final access = ref.watch(featureAccessProvider);
    final go = (String key) => ref.read(sidebarKeyProvider.notifier).set(key);

    final banners = [
      (
        icon: FontAwesomeIcons.rocket,
        title: l10n.overviewActionCreateTitle,
        body: l10n.overviewActionCreateBody,
        locked: false,
        onOpen: () => go(CatalogueScreen.sidebarKey),
        actions: [
          (
            label: l10n.overviewActionImportImage,
            onTap: () => go(CatalogueScreen.sidebarKey),
          ),
          (
            label: l10n.overviewActionLaunchVm,
            onTap: () => go(VmTableScreen.sidebarKey),
          ),
        ],
      ),
      (
        icon: FontAwesomeIcons.wandMagicSparkles,
        title: l10n.overviewActionAiTitle,
        body: l10n.overviewActionAiBody,
        locked: !access.canUseLlms,
        onOpen: () => go(LlmCatalogueScreen.sidebarKey),
        actions: [
          (
            label: l10n.overviewActionLoadDownloaded,
            onTap: () => go(LlmDownloadedScreen.sidebarKey),
          ),
          (
            label: l10n.overviewActionBrowseModels,
            onTap: () => go(LlmInstancesScreen.sidebarKey),
          ),
        ],
      ),
      (
        icon: FontAwesomeIcons.cubes,
        title: l10n.overviewActionServicesTitle,
        body: l10n.overviewActionServicesBody,
        locked: !access.canUseServices,
        onOpen: () => go(ServicesScreen.sidebarKey),
        actions: [
          (
            label: l10n.overviewActionBrowseServices,
            onTap: () => go(ServicesScreen.sidebarKey),
          ),
          (
            label: l10n.overviewActionViewDeployments,
            onTap: () => go(ServiceInstancesScreen.sidebarKey),
          ),
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final children = [
          for (final banner in banners)
            _ActionCard(
              icon: banner.icon,
              title: banner.title,
              body: banner.body,
              locked: banner.locked,
              onOpen: banner.onOpen,
              actions: banner.actions,
              equalHeight: wide,
            ),
        ];

        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(child: children[i]),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.locked,
    required this.onOpen,
    required this.actions,
    this.equalHeight = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool locked;
  final VoidCallback onOpen;
  final List<({String label, VoidCallback onTap})> actions;
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final radius = BorderRadius.circular(Brand.radius);

    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: locked ? null : onOpen,
        mouseCursor:
            locked ? SystemMouseCursors.basic : SystemMouseCursors.click,
        borderRadius: BorderRadius.only(
          topLeft: radius.topLeft,
          topRight: radius.topRight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Brand.primaryMuted,
                      borderRadius: BorderRadius.circular(Brand.radius),
                      border: Border.all(
                        color: Brand.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Center(
                      child: FaIcon(icon, size: 22, color: Brand.primary),
                    ),
                  ),
                  const Spacer(),
                  if (locked)
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.55),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 13,
                  height: 1.35,
                  color: onSurface.withValues(alpha: 0.72),
                ),
              ),
              if (equalHeight) const Spacer(),
            ],
          ),
        ),
      ),
    );

    final card = CatalogueSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (equalHeight) Expanded(child: content) else content,
          _ActionFooter(
            radius: radius,
            locked: locked,
            actions: actions,
          ),
        ],
      ),
    );

    return Opacity(
      opacity: locked ? 0.48 : 1,
      child: AbsorbPointer(
        absorbing: locked,
        child: equalHeight ? SizedBox.expand(child: card) : card,
      ),
    );
  }
}

class _ActionFooter extends StatelessWidget {
  const _ActionFooter({
    required this.radius,
    required this.locked,
    required this.actions,
  });

  final BorderRadius radius;
  final bool locked;
  final List<({String label, VoidCallback onTap})> actions;

  static const _rowHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerColor;

    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) Container(height: 1, color: divider),
          _FooterButton(
            label: actions[i].label,
            onTap: locked ? null : actions[i].onTap,
            outlined: i == 0,
            height: _rowHeight,
            borderRadius: i == actions.length - 1
                ? BorderRadius.only(
                    bottomLeft: radius.bottomLeft,
                    bottomRight: radius.bottomRight,
                  )
                : BorderRadius.zero,
            topBorder: i == 0,
            dividerColor: divider,
          ),
        ],
      ],
    );
  }
}

class _FooterButton extends StatefulWidget {
  const _FooterButton({
    required this.label,
    required this.onTap,
    required this.outlined,
    required this.height,
    required this.borderRadius,
    required this.topBorder,
    required this.dividerColor,
  });

  final String label;
  final VoidCallback? onTap;
  final bool outlined;
  final double height;
  final BorderRadius borderRadius;
  final bool topBorder;
  final Color dividerColor;

  @override
  State<_FooterButton> createState() => _FooterButtonState();
}

class _FooterButtonState extends State<_FooterButton> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final filled = !widget.outlined;

    Color background;
    Color foreground;
    if (filled) {
      background = _pressed
          ? Brand.primary.withValues(alpha: 0.82)
          : _hovered
              ? Brand.primary.withValues(alpha: 0.92)
              : Brand.primary;
      foreground = Brand.voidBlack;
    } else {
      background = _pressed
          ? Brand.primary.withValues(alpha: 0.18)
          : _hovered
              ? Brand.primary.withValues(alpha: 0.10)
              : Colors.transparent;
      foreground = Brand.primary;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled
          ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
          : null,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: widget.height,
          decoration: BoxDecoration(
            color: background,
            borderRadius: widget.borderRadius,
            border: Border(
              top: widget.topBorder
                  ? BorderSide(
                      color: widget.outlined
                          ? Brand.primary.withValues(alpha: 0.55)
                          : widget.dividerColor,
                    )
                  : BorderSide.none,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: Brand.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
