import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalogue/catalogue_surface.dart';
import '../page_surface.dart';
import '../providers.dart';
import 'terminal_tabs.dart';
import 'vm_details_bridge.dart';
import 'vm_details_general.dart';
import 'vm_details_mounts.dart';
import 'vm_details_resources.dart';

enum VmDetailsLocation { shells, details }

final vmScreenLocationProvider = NotifierProvider.autoDispose
    .family<VmScreenLocationNotifier, VmDetailsLocation, VmId>(
  VmScreenLocationNotifier.new,
);

class VmScreenLocationNotifier extends Notifier<VmDetailsLocation> {
  VmScreenLocationNotifier(this.arg);
  final VmId arg;

  @override
  VmDetailsLocation build() {
    return VmDetailsLocation.shells;
  }

  void set(VmDetailsLocation location) {
    state = location;
  }
}

enum ActiveEditPage { resources, bridge, mounts }

final activeEditPageProvider = NotifierProvider.autoDispose
    .family<ActiveEditPageNotifier, ActiveEditPage?, VmId>(
  ActiveEditPageNotifier.new,
);

class ActiveEditPageNotifier extends Notifier<ActiveEditPage?> {
  ActiveEditPageNotifier(this.id);
  final VmId id;

  @override
  ActiveEditPage? build() {
    ref.listen(
      vmInfoProvider(id).select((info) => info.instanceStatus.status),
      (_, status) {
        final isBridgeOrResources = [
          ActiveEditPage.bridge,
          ActiveEditPage.resources,
        ].contains(state);

        if (isBridgeOrResources && status != Status.STOPPED) {
          ref.invalidateSelf();
        }
      },
    );
    return null;
  }

  void set(ActiveEditPage? page) {
    state = page;
  }
}

class VmDetailsScreen extends ConsumerWidget {
  final VmId id;

  const VmDetailsScreen(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(vmScreenLocationProvider(id));

    return Scaffold(
      body: Column(
        children: [
          PageSurface(
            margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: VmDetailsHeader(id),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: CatalogueSurface(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Visibility(
                      visible: location == VmDetailsLocation.shells,
                      maintainState: true,
                      child: TerminalTabs(id),
                    ),
                    Visibility(
                      visible: location == VmDetailsLocation.details,
                      child: VmDetails(id),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VmDetails extends ConsumerWidget {
  final VmId id;

  const VmDetails(this.id, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeEditPage = ref.watch(activeEditPageProvider(id));

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DisableSection(
              active: activeEditPage,
              letEnabledFor: const [],
              child: GeneralDetails(id),
            ),
            const Divider(height: 60),
            DisableSection(
              active: activeEditPage,
              letEnabledFor: const [ActiveEditPage.resources],
              child: ResourcesDetails(id),
            ),
            const Divider(height: 60),
            DisableSection(
              active: activeEditPage,
              letEnabledFor: const [ActiveEditPage.bridge],
              child: BridgedDetails(id),
            ),
            const Divider(height: 60),
            DisableSection(
              active: activeEditPage,
              letEnabledFor: const [ActiveEditPage.mounts],
              child: MountDetails(id),
            ),
          ],
        ),
      ),
    );
  }
}

class DisableSection extends StatelessWidget {
  final ActiveEditPage? active;
  final List<ActiveEditPage> letEnabledFor;
  final Widget child;

  const DisableSection({
    super.key,
    required this.active,
    required this.letEnabledFor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = active != null && !letEnabledFor.contains(active);
    return IgnorePointer(
      ignoring: disabled,
      child: Opacity(opacity: disabled ? 0.5 : 1.0, child: child),
    );
  }
}
