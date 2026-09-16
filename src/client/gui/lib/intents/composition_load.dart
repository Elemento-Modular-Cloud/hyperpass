import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../grpc_client.dart';
import '../l10n/app_localizations.dart';
import '../llm/providers.dart';
import '../providers.dart';
import '../services/compose/compose_graph.dart';
import '../services/compose/compose_store.dart';
import '../services/service_library.dart';
import '../widgets/resource_meter.dart';

/// CPU and RAM reserved by one composition versus the host totals.
class CompositionLoad {
  const CompositionLoad({
    required this.cpus,
    required this.cpuHost,
    required this.memBytes,
    required this.memHost,
  });

  final int cpus;
  final int cpuHost;
  final int memBytes;
  final int memHost;

  bool get hasHost => cpuHost > 0 || memHost > 0;

  double get cpuRatio => cpuHost <= 0 ? 0 : cpus / cpuHost;

  double get memRatio => memHost <= 0 ? 0 : memBytes / memHost;
}

int parseOccupancyCpus(String raw) => int.tryParse(raw.trim()) ?? 0;

int parseOccupancyBytes(String raw) {
  return parseComposeByteSize(raw) ?? int.tryParse(raw.trim()) ?? 0;
}

({int cpus, int memBytes}) occupancyOfVm(TaggedVmInfo info) {
  return (
    cpus: parseOccupancyCpus(info.cpuCount),
    memBytes: parseOccupancyBytes(info.memoryTotal),
  );
}

({int cpus, int memBytes}) occupancyOfLlm(LoadedModelInfo model) {
  return (cpus: 0, memBytes: model.memoryClaimed.toInt());
}

CompositionLoad compositionLoadFromMembers({
  required Iterable<({String intent, int cpus, int memBytes})> members,
  required String intentName,
  required int cpuHost,
  required int memHost,
}) {
  var cpus = 0;
  var memBytes = 0;
  for (final member in members) {
    if (member.intent != intentName) continue;
    cpus += member.cpus;
    memBytes += member.memBytes;
  }
  return CompositionLoad(
    cpus: cpus,
    cpuHost: cpuHost,
    memBytes: memBytes,
    memHost: memHost,
  );
}

/// Reserved occupancy for named instances. Scheduler claims win when present;
/// otherwise the caller-supplied row totals are used.
CompositionLoad compositionLoadFromReserved({
  required int reservedCpus,
  required int reservedMemBytes,
  required Set<String> instanceNames,
  required Iterable<({String name, int cpus, int memBytes})> claims,
  required int cpuHost,
  required int memHost,
}) {
  var claimedCpus = 0;
  var claimedMem = 0;
  var matched = false;
  for (final claim in claims) {
    if (!instanceNames.contains(claim.name)) continue;
    matched = true;
    claimedCpus += claim.cpus;
    claimedMem += claim.memBytes;
  }
  return CompositionLoad(
    cpus: matched ? claimedCpus : reservedCpus,
    cpuHost: cpuHost,
    memBytes: matched ? claimedMem : reservedMemBytes,
    memHost: memHost,
  );
}

CompositionLoad compositionLoadFromInstances({
  required String intentName,
  required Iterable<TaggedVmInfo> instances,
  required Iterable<LoadedModelInfo> models,
  required int cpuHost,
  required int memHost,
}) {
  return compositionLoadFromMembers(
    members: [
      for (final info in instances)
        (
          intent: info.info.intent,
          cpus: occupancyOfVm(info).cpus,
          memBytes: occupancyOfVm(info).memBytes,
        ),
      for (final model in models)
        (
          intent: model.intent,
          cpus: occupancyOfLlm(model).cpus,
          memBytes: occupancyOfLlm(model).memBytes,
        ),
    ],
    intentName: intentName,
    cpuHost: cpuHost,
    memHost: memHost,
  );
}

CompositionLoad compositionLoadFromGraph({
  required ComposeGraph graph,
  required MarketplaceLibrary library,
  required int cpuHost,
  required int memHost,
}) {
  var cpus = 0;
  var memBytes = 0;
  for (final node in graph.nodes) {
    if (node.kind == ComposeNodeKind.llm) continue;
    final service = node.isService ? library.lookup(node.serviceId) : null;
    cpus += composeResolvedCpus(node, service);
    memBytes += composeResolvedMemBytes(node, service);
  }
  return CompositionLoad(
    cpus: cpus,
    cpuHost: cpuHost,
    memBytes: memBytes,
    memHost: memHost,
  );
}

/// Compact CPU / RAM share of the host reserved by [load].
class CompositionLoadMeters extends StatelessWidget {
  const CompositionLoadMeters({
    required this.load,
    this.compact = true,
    super.key,
  });

  final CompositionLoad load;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!load.hasHost) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: ResourceMeter(
            label: l10n.hostCpuLabel,
            valueText: '${load.cpus} / ${load.cpuHost}',
            progress: load.cpuRatio,
            icon: FontAwesomeIcons.microchip,
            compact: compact,
          ),
        ),
        SizedBox(width: compact ? 12 : 16),
        Expanded(
          child: ResourceMeter(
            label: l10n.hostMemoryLabel,
            valueText:
                '${formatResourceBytes('${load.memBytes}')} / ${formatResourceBytes('${load.memHost}')}',
            progress: load.memRatio,
            icon: FontAwesomeIcons.memory,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

/// Live reserved CPU / RAM for a named composition (or untagged instances).
class IntentCompositionLoad extends ConsumerWidget {
  const IntentCompositionLoad({
    required this.intentName,
    this.instanceNames = const {},
    this.reservedCpus = 0,
    this.reservedMemBytes = 0,
    this.compact = true,
    super.key,
  });

  final String intentName;
  final Set<String> instanceNames;
  final int reservedCpus;
  final int reservedMemBytes;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daemon = ref.watch(daemonInfoProvider).asData?.value;
    if (daemon == null) return const SizedBox.shrink();
    final cpuHost = daemon.cpus;
    final memHost = daemon.memory.toInt();

    var load = compositionLoadFromReserved(
      reservedCpus: reservedCpus,
      reservedMemBytes: reservedMemBytes,
      instanceNames: instanceNames,
      claims: [
        for (final claim in daemon.claims)
          (
            name: claim.name,
            cpus: claim.cpus,
            memBytes: claim.memoryBytes.toInt(),
          ),
      ],
      cpuHost: cpuHost,
      memHost: memHost,
    );

    if (load.cpus == 0 && load.memBytes == 0) {
      load = compositionLoadFromInstances(
        intentName: intentName,
        instances: ref.watch(allActiveVmInfosWithServicesProvider),
        models: ref.watch(loadedModelsProvider).asData?.value.models ?? const [],
        cpuHost: cpuHost,
        memHost: memHost,
      );
    }

    if (load.cpus == 0 && load.memBytes == 0) {
      final graphs = loadComposeGraphs(ref.watch(sharedPreferencesProvider));
      final graph = graphs[intentName];
      final library = ref.watch(marketplaceLibraryProvider).asData?.value;
      if (graph != null && library != null) {
        load = compositionLoadFromGraph(
          graph: graph,
          library: library,
          cpuHost: cpuHost,
          memHost: memHost,
        );
      }
    }

    return CompositionLoadMeters(
      key: ValueKey('composition-load-$intentName'),
      load: load,
      compact: compact,
    );
  }
}
