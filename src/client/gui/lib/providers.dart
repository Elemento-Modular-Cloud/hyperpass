import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basics/basics.dart';
import 'package:built_collection/built_collection.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grpc/grpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daemon_source.dart';
import 'ffi.dart';
import 'grpc_client.dart';
import 'logger.dart';
import 'multipass_discovery.dart';

export 'daemon_source.dart';
export 'grpc_client.dart';

late final ProviderContainer providerContainer;

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden');
});

final ffiAvailableProvider = Provider((ref) {
  return isFFIAvailable;
});

GrpcClient _buildGrpcClient({
  required Uri address,
  required List<int> certificate,
  required List<int> certificateKey,
  required List<int> rootCertificate,
  BadCertificateHandler? onBadCertificate,
}) {
  final channelCredentials = CustomChannelCredentials(
    authority: 'localhost',
    certificate: certificate,
    certificateKey: certificateKey,
    rootCertificate: rootCertificate,
    onBadCertificate: onBadCertificate,
  );

  return GrpcClient(
    RpcClient(
      ClientChannel(
        address.scheme == InternetAddressType.unix.name.toLowerCase()
            ? InternetAddress(address.path, type: InternetAddressType.unix)
            : address.host,
        port: address.port,
        options: ChannelOptions(credentials: channelCredentials),
        channelShutdownHandler: () => logger.w('gRPC channel shut down'),
      ),
    ),
  );
}

/// Primary Hyperpass daemon client (required).
final grpcClientProvider = Provider((ref) {
  if (!ref.watch(ffiAvailableProvider)) {
    throw ffiLoadError ?? Exception('FFI library not available');
  }

  final address = getServerAddress();
  final certPair = getCertPair();
  final rootCert = getRootCert();

  return _buildGrpcClient(
    address: address,
    certificate: certPair.cert,
    certificateKey: certPair.key,
    rootCertificate: rootCert,
  );
});

const showMultipassInstancesKey = 'showMultipassInstances';

bool _showMultipassEnabled(Ref ref) {
  final value = ref.watch(guiSettingProvider(showMultipassInstancesKey));
  return value != 'false';
}

/// Best-effort Multipass daemon client. Null when unavailable or disabled.
final multipassGrpcClientProvider = Provider<GrpcClient?>((ref) {
  if (!_showMultipassEnabled(ref)) return null;

  final config = discoverMultipassConnection();
  if (config == null) return null;

  try {
    return _buildGrpcClient(
      address: config.address,
      certificate: config.clientCert,
      certificateKey: config.clientKey,
      rootCertificate: config.rootCert,
      // Multipass UDS certs are CN=localhost without SANs; Dart rejects them
      // unless we allow that identity after pinning the Multipass root CA.
      onBadCertificate: allowMultipassDaemonCertificate,
    );
  } catch (e, st) {
    logger.w('Failed to create Multipass gRPC client', error: e, stackTrace: st);
    return null;
  }
});

GrpcClient? grpcClientFor(Ref ref, DaemonSource source) {
  return switch (source) {
    DaemonSource.hyperpass => ref.read(grpcClientProvider),
    DaemonSource.multipass => ref.read(multipassGrpcClientProvider),
  };
}

/// True when Multipass is present but rejected the client cert (needs authenticate).
final multipassNeedsAuthProvider =
    NotifierProvider<MultipassNeedsAuthNotifier, bool>(
  MultipassNeedsAuthNotifier.new,
);

class MultipassNeedsAuthNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final hyperpassVmInfosStreamProvider = StreamProvider<List<VmInfo>>((ref) async* {
  final grpcClient = ref.watch(grpcClientProvider);
  Object? lastError;
  while (true) {
    final timer = Future.delayed(1900.milliseconds);
    try {
      yield await grpcClient.info();
      lastError = null;
    } catch (error, stackTrace) {
      if (error != lastError) {
        logger.e('Error on polling Hyperpass info',
            error: error, stackTrace: stackTrace);
        yield* Stream.error(error, stackTrace);
      }
      lastError = error;
    }
    await timer;
    await Future.delayed(100.milliseconds);
  }
});

/// True when the last Multipass info poll succeeded.
final multipassOnlineProvider =
    NotifierProvider<MultipassOnlineNotifier, bool>(MultipassOnlineNotifier.new);

class MultipassOnlineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

/// Sidebar-facing Multipass connectivity for the status row.
enum MultipassSidebarStatus { hidden, online, offline, needsAuth, disabled }

final multipassSidebarStatusProvider = Provider<MultipassSidebarStatus>((ref) {
  if (!_showMultipassEnabled(ref)) {
    return MultipassSidebarStatus.disabled;
  }
  if (ref.watch(multipassNeedsAuthProvider)) {
    return MultipassSidebarStatus.needsAuth;
  }
  if (ref.watch(multipassGrpcClientProvider) == null) {
    return MultipassSidebarStatus.offline;
  }
  return ref.watch(multipassOnlineProvider)
      ? MultipassSidebarStatus.online
      : MultipassSidebarStatus.offline;
});

final multipassVmInfosStreamProvider =
    StreamProvider<List<VmInfo>>((ref) async* {
  final client = ref.watch(multipassGrpcClientProvider);
  Object? lastError;
  while (true) {
    final timer = Future.delayed(1900.milliseconds);
    if (client == null) {
      ref.read(multipassOnlineProvider.notifier).set(false);
      yield const [];
    } else {
      try {
        final infos = await client.info();
        if (ref.read(multipassNeedsAuthProvider)) {
          ref.read(multipassNeedsAuthProvider.notifier).set(false);
        }
        ref.read(multipassOnlineProvider.notifier).set(true);
        yield infos;
        lastError = null;
      } catch (error, stackTrace) {
        final message = error is GrpcError ? (error.message ?? '') : '$error';
        final lower = message.toLowerCase();
        final unauthenticated = error is GrpcError &&
            (error.code == StatusCode.unauthenticated ||
                lower.contains('unauthenticated') ||
                lower.contains('not authenticated') ||
                lower.contains('access denied'));
        if (unauthenticated) {
          ref.read(multipassNeedsAuthProvider.notifier).set(true);
        }
        ref.read(multipassOnlineProvider.notifier).set(false);
        if (error != lastError) {
          logger.w('Error on polling Multipass info',
              error: error, stackTrace: stackTrace);
        }
        lastError = error;
        yield const [];
      }
    }
    await timer;
    await Future.delayed(100.milliseconds);
  }
});

/// Merged Hyperpass + Multipass instance stream (tagged).
///
/// Multipass instances are included even when Hyperpass is offline/erroring.
final vmInfosStreamProvider = Provider<AsyncValue<List<TaggedVmInfo>>>((ref) {
  final hyperpass = ref.watch(hyperpassVmInfosStreamProvider);
  final multipass = ref.watch(multipassVmInfosStreamProvider);

  final hpInfos = hyperpass.asData?.value;
  final mpInfos = multipass.asData?.value ?? const <VmInfo>[];

  if (hpInfos == null && mpInfos.isEmpty) {
    if (hyperpass.hasError) {
      return AsyncValue.error(hyperpass.error!, hyperpass.stackTrace!);
    }
    return const AsyncValue.loading();
  }

  final tagged = <TaggedVmInfo>[
    for (final info in hpInfos ?? const <VmInfo>[])
      TaggedVmInfo(id: hyperpassVm(info.name), info: info),
    for (final info in mpInfos)
      TaggedVmInfo(id: multipassVm(info.name), info: info),
  ]..sort((a, b) {
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      return a.source.index.compareTo(b.source.index);
    });
  return AsyncValue.data(tagged);
});

final daemonAvailableProvider = Provider((ref) {
  if (!ref.watch(ffiAvailableProvider)) {
    return false;
  }

  final error = ref.watch(hyperpassVmInfosStreamProvider).error;
  if (error == null) return true;
  if (error case GrpcError grpcError) {
    final message = grpcError.message ?? '';
    if (message.contains('failed to obtain exit status for remote process')) {
      return true;
    }
  }
  return false;
});

final daemonInfoProvider = StreamProvider<DaemonInfoReply>((ref) async* {
  final grpcClient = ref.watch(grpcClientProvider);
  while (true) {
    final timer = Future.delayed(1900.milliseconds);
    try {
      yield await grpcClient.daemonInfo();
    } catch (error, stackTrace) {
      logger.e('Error on polling daemon_info', error: error, stackTrace: stackTrace);
      yield* Stream.error(error, stackTrace);
    }
    await timer;
    await Future.delayed(100.milliseconds);
  }
});

class AllVmInfosNotifier extends Notifier<List<TaggedVmInfo>> {
  @override
  List<TaggedVmInfo> build() {
    return ref.watch(vmInfosStreamProvider).when(
          data: (data) => data,
          loading: () => const [],
          error: (_, __) => const [],
        );
  }

  Future<void> update() async {
    final hp = await ref.read(grpcClientProvider).info();
    final mpClient = ref.read(multipassGrpcClientProvider);
    List<VmInfo> mp = const [];
    if (mpClient != null) {
      try {
        mp = await mpClient.info();
      } catch (_) {
        mp = const [];
      }
    }
    state = [
      for (final info in hp)
        TaggedVmInfo(id: hyperpassVm(info.name), info: info),
      for (final info in mp)
        TaggedVmInfo(id: multipassVm(info.name), info: info),
    ];
  }
}

final allVmInfosProvider =
    NotifierProvider<AllVmInfosNotifier, List<TaggedVmInfo>>(
  AllVmInfosNotifier.new,
);

const serviceInstanceBindingsKey = 'local.service-instance-bindings';

/// Local name → marketplace service id. Survives daemon metadata wipes (QEMU
/// used to replace the whole metadata object on start).
class ServiceInstanceBindingsNotifier extends Notifier<BuiltMap<String, String>> {
  @override
  BuiltMap<String, String> build() {
    final raw =
        ref.watch(sharedPreferencesProvider).getString(serviceInstanceBindingsKey);
    if (raw == null || raw.isEmpty) return BuiltMap();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return BuiltMap();
      return BuiltMap({
        for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
      });
    } catch (_) {
      return BuiltMap();
    }
  }

  void bind(String instanceName, String serviceId) {
    if (instanceName.isEmpty || serviceId.isEmpty) return;
    if (state[instanceName] == serviceId) return;
    final next = state.rebuild((b) => b[instanceName] = serviceId);
    ref.read(sharedPreferencesProvider).setString(
          serviceInstanceBindingsKey,
          jsonEncode(next.toMap()),
        );
    state = next;
  }

  void unbind(String instanceName) {
    if (!state.containsKey(instanceName)) return;
    final next = state.rebuild((b) => b.remove(instanceName));
    ref.read(sharedPreferencesProvider).setString(
          serviceInstanceBindingsKey,
          jsonEncode(next.toMap()),
        );
    state = next;
  }
}

final serviceInstanceBindingsProvider = NotifierProvider<
    ServiceInstanceBindingsNotifier, BuiltMap<String, String>>(
  ServiceInstanceBindingsNotifier.new,
);

String effectiveServiceId(
  DetailedInfoItem info,
  BuiltMap<String, String> bindings,
) {
  if (info.serviceId.isNotEmpty) return info.serviceId;
  return bindings[info.name] ?? '';
}

TaggedVmInfo withEffectiveServiceId(
  TaggedVmInfo tagged,
  BuiltMap<String, String> bindings,
) {
  final sid = effectiveServiceId(tagged.info, bindings);
  if (sid.isEmpty || tagged.info.serviceId == sid) return tagged;
  final copy = tagged.info.deepCopy()..serviceId = sid;
  return TaggedVmInfo(id: tagged.id, info: copy);
}

/// True when this Hyperpass VM was launched as a marketplace service instance.
bool isServiceVmInfo(DetailedInfoItem info) => info.serviceId.isNotEmpty;

/// Every non-deleted VM (plain + service) plus in-flight launches.
final allActiveVmInfosProvider = Provider((ref) {
  final existingVms = ref
      .watch(allVmInfosProvider)
      .where((info) => info.instanceStatus.status != Status.DELETED)
      .toBuiltList();
  final existingIds = existingVms.map((i) => i.id).toSet();
  final launchingVms = ref.watch(launchingVmsProvider).where((info) {
    return !existingIds.contains(info.id);
  });

  return [
    ...existingVms,
    ...launchingVms,
  ]..sort((a, b) {
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      return a.source.index.compareTo(b.source.index);
    });
});

/// Active VMs with local service bindings applied when the daemon tag is missing.
final allActiveVmInfosWithServicesProvider = Provider((ref) {
  final bindings = ref.watch(serviceInstanceBindingsProvider);
  return [
    for (final info in ref.watch(allActiveVmInfosProvider))
      withEffectiveServiceId(info, bindings),
  ];
});

/// Plain VMs only — marketplace service instances are listed under Services.
final vmInfosProvider = Provider((ref) {
  return ref
      .watch(allActiveVmInfosWithServicesProvider)
      .where((info) => !isServiceVmInfo(info.info))
      .toList();
});

/// Marketplace services that run as tagged Hyperpass VMs.
final serviceInstanceInfosProvider = Provider((ref) {
  return ref
      .watch(allActiveVmInfosWithServicesProvider)
      .where((info) => isServiceVmInfo(info.info))
      .toList();
});

final serviceInstanceIdsProvider = Provider((ref) {
  return {
    for (final info in ref.watch(serviceInstanceInfosProvider)) info.id,
  }.toBuiltSet();
});

final vmInfosMapProvider = Provider((ref) {
  return {for (final i in ref.watch(vmInfosProvider)) i.id: i};
});

/// All active Hyperpass/Multipass VMs, including marketplace service instances.
/// Used by shell/status lookups that need any VM by id.
final allVmInfosMapProvider = Provider((ref) {
  return {
    for (final i in ref.watch(allActiveVmInfosWithServicesProvider)) i.id: i,
  };
});

class VmInfoNotifier extends Notifier<DetailedInfoItem> {
  VmInfoNotifier(this.arg);
  final VmId arg;

  @override
  DetailedInfoItem build() {
    return ref.watch(allVmInfosMapProvider)[arg]?.info ?? DetailedInfoItem();
  }
}

final vmInfoProvider = NotifierProvider.autoDispose
    .family<VmInfoNotifier, DetailedInfoItem, VmId>(VmInfoNotifier.new);

final vmStatusesProvider = Provider((ref) {
  return BuiltMap<VmId, Status>({
    for (final entry in ref.watch(vmInfosMapProvider).entries)
      entry.key: entry.value.instanceStatus.status,
  });
});

final vmIdsProvider = Provider((ref) {
  return ref.watch(vmStatusesProvider).keys.toBuiltSet();
});

/// Backwards-compatible name; now returns VmIds.
final vmNamesProvider = vmIdsProvider;

/// Hyperpass instance names only (for launch uniqueness / petnames).
/// Includes service instances so names cannot collide across surfaces.
final hyperpassVmNamesProvider = Provider((ref) {
  return ref
      .watch(allActiveVmInfosProvider)
      .where((info) => info.source == DaemonSource.hyperpass)
      .map((info) => info.name)
      .toBuiltSet();
});

final deletedVmsProvider = Provider((ref) {
  return ref
      .watch(allVmInfosProvider)
      .where((info) =>
          info.source == DaemonSource.hyperpass &&
          info.instanceStatus.status == Status.DELETED)
      .map((info) => info.name)
      .toBuiltSet();
});

class LaunchingVmsNotifier extends Notifier<BuiltList<TaggedVmInfo>> {
  @override
  BuiltList<TaggedVmInfo> build() {
    final vms = stateOrNull ?? BuiltList();

    return vms;
  }

  void add(LaunchRequest request, {String os = ''}) {
    final vms = state;
    if (request.serviceId.isNotEmpty) {
      ref
          .read(serviceInstanceBindingsProvider.notifier)
          .bind(request.instanceName, request.serviceId);
    }
    state = vms.rebuild((builder) {
      builder.add(
        TaggedVmInfo(
          id: hyperpassVm(request.instanceName),
          info: DetailedInfoItem(
            name: request.instanceName,
            cpuCount: request.numCores.toString(),
            diskTotal: request.diskSpace,
            memoryTotal: request.memSize,
            serviceId:
                request.serviceId.isEmpty ? null : request.serviceId,
            instanceInfo: InstanceDetails(
              currentRelease: request.image,
              os: os,
            ),
          ),
        ),
      );
    });
  }

  void remove(String name) {
    final id = hyperpassVm(name);
    final vms = state;
    state = vms.rebuild((builder) {
      builder.removeWhere((info) => info.id == id);
    });
  }

  @override
  bool updateShouldNotify(
    BuiltList<TaggedVmInfo> previous,
    BuiltList<TaggedVmInfo> next,
  ) {
    return previous != next;
  }
}

final launchingVmsProvider =
    NotifierProvider<LaunchingVmsNotifier, BuiltList<TaggedVmInfo>>(
  LaunchingVmsNotifier.new,
);

final isLaunchingProvider = Provider.autoDispose.family<bool, VmId>((
  ref,
  id,
) {
  final launchingVms = ref.watch(launchingVmsProvider);
  return launchingVms.any((info) => info.id == id);
});

class ClientSettingNotifier extends Notifier<String> {
  ClientSettingNotifier(this.arg);
  final String arg;
  final file = File(settingsFile());

  @override
  String build() {
    file.parent.create(recursive: true).then(
          (dir) => dir
              .watch()
              .where((event) => event.path == file.path)
              .first
              .whenComplete(() => Timer(250.milliseconds, ref.invalidateSelf)),
        );
    return getSetting(arg);
  }

  void set(String value) => setSetting(arg, value);

  @override
  bool updateShouldNotify(String previous, String next) => previous != next;
}

const primaryNameKey = 'client.primary-name';
final clientSettingProvider = NotifierProvider.autoDispose
    .family<ClientSettingNotifier, String, String>(ClientSettingNotifier.new);

class DaemonSettingNotifier extends AsyncNotifier<String> {
  DaemonSettingNotifier(this.arg);
  final String arg;

  @override
  Future<String> build() async {
    return ref.watch(daemonAvailableProvider)
        ? await ref.watch(grpcClientProvider).get(arg)
        : state.when(
            data: (data) => data,
            loading: () => throw StateError('Daemon not available'),
            error: (_, __) => throw StateError('Daemon not available'),
          );
  }

  Future<void> set(String value) async {
    state = AsyncValue.data(value);
    try {
      await ref.read(grpcClientProvider).set(arg, value);
    } catch (_) {
      Timer(100.milliseconds, ref.invalidateSelf);
      rethrow;
    }
  }

  @override
  bool updateShouldNotify(
    AsyncValue<String> previous,
    AsyncValue<String> next,
  ) {
    return previous != next;
  }
}

final trayMenuDataProvider = Provider.autoDispose((ref) {
  final hyperpassUp = ref.watch(daemonAvailableProvider);
  final multipassClient = ref.watch(multipassGrpcClientProvider);
  if (!hyperpassUp && multipassClient == null) return null;
  return ref.watch(vmStatusesProvider);
});

final daemonVersionProvider = NotifierProvider<DaemonVersionNotifier, String>(
  DaemonVersionNotifier.new,
);

class DaemonVersionNotifier extends Notifier<String> {
  @override
  String build() {
    if (ref.watch(daemonAvailableProvider)) {
      ref
          .watch(grpcClientProvider)
          .version()
          .catchError((_) => 'failed to get version')
          .then((version) => state = version);
    }
    return 'loading...';
  }
}

const driverKey = 'local.driver';
const bridgedNetworkKey = 'local.bridged-network';
const privilegedMountsKey = 'local.privileged-mounts';
const passphraseKey = 'local.passphrase';
final daemonSettingProvider = AsyncNotifierProvider.autoDispose
    .family<DaemonSettingNotifier, String, String>(DaemonSettingNotifier.new);

enum VmResource { cpus, memory, disk, bridged }

typedef VmResourceKey = ({VmId id, VmResource resource});

class VmResourceNotifier extends AsyncNotifier<String> {
  VmResourceNotifier(this.arg);
  final VmResourceKey arg;

  @override
  Future<String> build() async {
    final (:id, :resource) = arg;
    final launchingVm = ref.watch(
      launchingVmsProvider.select((infos) {
        return infos.firstWhereOrNull((info) => info.id == id);
      }),
    );

    if (launchingVm != null) {
      return switch (resource) {
        VmResource.cpus => launchingVm.cpuCount,
        VmResource.memory => launchingVm.memoryTotal,
        VmResource.disk => launchingVm.diskTotal,
        VmResource.bridged => 'false',
      };
    }

    final client = grpcClientFor(ref, id.source);
    if (client == null) {
      throw StateError('No client for ${id.source}');
    }
    final key = 'local.${id.name}.${resource.name}';
    // Multipass and Hyperpass both expose local.<name>.* settings via get.
    return await client.get(key);
  }

  Future<void> set(String value) async {
    final (:id, :resource) = arg;
    final key = 'local.${id.name}.${resource.name}';
    if (id.source == DaemonSource.hyperpass) {
      ref.read(daemonSettingProvider(key).notifier).set(value);
      return;
    }
    final client = grpcClientFor(ref, id.source);
    if (client == null) return;
    await client.set(key, value);
  }
}

final vmResourceProvider = AsyncNotifierProvider.autoDispose
    .family<VmResourceNotifier, String, VmResourceKey>(VmResourceNotifier.new);

class GuiSettingNotifier extends Notifier<String?> {
  GuiSettingNotifier(this.arg);
  final String arg;

  @override
  String? build() {
    final sharedPreferences = ref.read(sharedPreferencesProvider);
    final defaultValues = {
      onAppCloseKey: 'ask',
      themeModeKey: 'system',
      showMultipassInstancesKey: 'true',
    };

    return sharedPreferences.getString(arg) ?? defaultValues[arg];
  }

  void set(String value) {
    final sharedPreferences = ref.read(sharedPreferencesProvider);
    sharedPreferences.setString(arg, value);
    state = value;
  }

  @override
  bool updateShouldNotify(String? previous, String? next) => previous != next;
}

const onAppCloseKey = 'onAppClose';
const hotkeyKey = 'hotkey';
const askTerminalCloseKey = 'askTerminalClose';
const themeModeKey = 'themeMode';
final guiSettingProvider = NotifierProvider.autoDispose
    .family<GuiSettingNotifier, String?, String>(GuiSettingNotifier.new);

final networksProvider =
    FutureProvider.autoDispose<BuiltSet<String>>((ref) async {
  final driver = ref.watch(daemonSettingProvider(driverKey)).when(
        data: (data) => data,
        loading: () => null,
        error: (_, __) => null,
      );
  if (driver != null && ref.watch(daemonAvailableProvider)) {
    final networks = await ref.watch(grpcClientProvider).networks();
    return BuiltSet<String>(networks);
  }
  return BuiltSet<String>();
});

class SessionTerminalFontSizeNotifier extends Notifier<double> {
  static const defaultFontSize = 13.0;

  @override
  double build() => defaultFontSize;

  void set(double value) => state = value;
}

final sessionTerminalFontSizeProvider =
    NotifierProvider<SessionTerminalFontSizeNotifier, double>(
        SessionTerminalFontSizeNotifier.new);

/// Runs a manage RPC against each daemon represented in [ids].
Future<void> runManagedAction({
  required GrpcClient? Function(DaemonSource source) clientFor,
  required Iterable<VmId> ids,
  required Future<void> Function(GrpcClient client, Iterable<String> names)
      action,
}) async {
  final bySource = <DaemonSource, List<String>>{};
  for (final id in ids) {
    bySource.putIfAbsent(id.source, () => []).add(id.name);
  }
  await Future.wait([
    for (final entry in bySource.entries)
      () async {
        final client = clientFor(entry.key);
        if (client == null) {
          throw StateError('${entry.key.label} daemon is unavailable');
        }
        await action(client, entry.value);
      }(),
  ]);
}
