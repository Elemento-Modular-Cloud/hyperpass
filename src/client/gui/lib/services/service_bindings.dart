import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'service_status.dart';

final _discoveryInFlight = <String>{};

/// Keeps local bindings in sync with daemon tags and rediscovers guests that
/// expose elemento service-info but lost their host-side service_id (e.g. after
/// an older daemon wiped metadata on QEMU start).
final serviceInstanceSyncProvider = Provider<void>((ref) {
  void sync(List<TaggedVmInfo> vms) {
    final bindings = ref.read(serviceInstanceBindingsProvider);
    final bindingsNotifier =
        ref.read(serviceInstanceBindingsProvider.notifier);
    final grpc = ref.read(grpcClientProvider);

    for (final vm in vms) {
      if (vm.source != DaemonSource.elp) continue;

      if (vm.info.serviceId.isNotEmpty) {
        bindingsNotifier.bind(vm.name, vm.info.serviceId);
        continue;
      }

      if (bindings.containsKey(vm.name)) continue;
      if (vm.instanceStatus.status != Status.RUNNING) continue;
      if (!_discoveryInFlight.add(vm.name)) continue;

      unawaited(() async {
        try {
          final status = await fetchServiceGuestStatus(
            grpc: grpc,
            instanceName: vm.name,
          );
          final sid = status.info?.service.trim() ?? '';
          if (sid.isNotEmpty) {
            ref
                .read(serviceInstanceBindingsProvider.notifier)
                .bind(vm.name, sid);
          }
        } catch (_) {
          // Guest may still be booting; a later poll retries.
        } finally {
          _discoveryInFlight.remove(vm.name);
        }
      }());
    }
  }

  ref.listen<List<TaggedVmInfo>>(allActiveVmInfosProvider, (_, vms) {
    sync(vms);
  });
  sync(ref.read(allActiveVmInfosProvider));
});
