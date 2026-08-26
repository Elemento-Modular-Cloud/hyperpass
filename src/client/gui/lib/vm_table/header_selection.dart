import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import 'vm_table_headers.dart';

class EnabledHeadersNotifier extends Notifier<BuiltMap<String, bool>> {
  @override
  BuiltMap<String, bool> build() {
    return {for (final h in headers) h.name: true}.build();
  }

  void toggleHeader(String name, bool isSelected) {
    state = state.rebuild((set) => set[name] = isSelected);
  }
}

final enabledHeadersProvider =
    NotifierProvider<EnabledHeadersNotifier, BuiltMap<String, bool>>(
  EnabledHeadersNotifier.new,
);

class HeaderSelectionTile extends ConsumerWidget {
  final String name;
  final String label;

  const HeaderSelectionTile(this.name, this.label, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledHeaders = ref.watch(enabledHeadersProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return CheckboxListTile(
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: TextStyle(color: onSurface)),
      value: enabledHeaders[name],
      onChanged: (isSelected) => ref
          .read(enabledHeadersProvider.notifier)
          .toggleHeader(name, isSelected!),
    );
  }
}

class HeaderSelection extends StatelessWidget {
  const HeaderSelection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final columnLabels = {
      'STATE': l10n.vmStatState,
      'CPU USAGE': l10n.vmStatCpuUsage,
      'MEMORY USAGE': l10n.vmStatMemoryUsage,
      'DISK USAGE': l10n.vmStatDiskUsage,
      'IMAGE': l10n.vmStatImage,
      'PRIVATE IP': l10n.vmStatPrivateIp,
      'PUBLIC IP': l10n.vmStatPublicIp,
    };
    return PopupMenuButton(
      position: PopupMenuPosition.under,
      itemBuilder: (_) => headers.skip(2).map((h) {
        return PopupMenuItem<void>(
          padding: EdgeInsets.zero,
          enabled: false,
          child: HeaderSelectionTile(h.name, columnLabels[h.name] ?? h.name),
        );
      }).toList(),
      child: Container(
        width: 120,
        height: 42,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(color: onSurface.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SvgPicture.asset(
              'assets/settings.svg',
              colorFilter: ColorFilter.mode(onSurface, BlendMode.srcIn),
            ),
            Text(
              l10n.vmTableColumnsButton,
              style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
