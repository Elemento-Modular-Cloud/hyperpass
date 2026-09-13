import 'dart:math';

import '../catalogue/launch_form.dart';
import '../providers.dart';
import '../vm_details/mapping_slider.dart';
import 'gateway_ca.dart';
import 'service_cloud_init.dart';
import 'service_library.dart';

int serviceCpus(MarketplaceService service) =>
    max(defaultCpus, service.resources.minCpu);

int serviceMemoryBytes(MarketplaceService service) =>
    max(defaultRam, service.resources.minMemoryGb.gibi);

/// Base VM disk plus everything the manifest wants to persist. The rendered
/// cloud-init grows the root filesystem to fill it.
int serviceDiskBytes(MarketplaceService service) =>
    defaultDisk + service.totalStorageGb.gibi;

/// Name used when a service's cloud-init is saved into the user's named library.
String serviceCloudInitName(MarketplaceService service) =>
    service.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');

/// Builds the intent-member RPC body for a marketplace service, including
/// rendered cloud-init and `service_id` so the instance stays a Deployment.
IntentMemberRequest buildServiceIntentMember({
  required MarketplaceService service,
  required String role,
  Map<String, String> variables = const {},
  String? gatewayCaPem,
  int? numCores,
  String? memSize,
  String? diskSpace,
}) {
  final member = IntentMemberRequest(
    role: role,
    numCores: numCores ?? serviceCpus(service),
    memSize: memSize ?? '${serviceMemoryBytes(service)}B',
    diskSpace: diskSpace ?? '${serviceDiskBytes(service)}B',
    serviceId: service.id,
  );
  member.cloudInitUserData = renderServiceCloudInit(
    service,
    variables: variables,
    gatewayCaPem: gatewayCaPem,
  );
  return member;
}

/// Fetches the gateway CA (best-effort) and builds a member request.
Future<IntentMemberRequest> buildServiceIntentMemberWithGatewayCa({
  required MarketplaceService service,
  required String role,
  Map<String, String> variables = const {},
  int? numCores,
  String? memSize,
  String? diskSpace,
}) async {
  String? pem;
  try {
    pem = await fetchGatewayCaPem();
  } catch (_) {
    pem = null;
  }
  return buildServiceIntentMember(
    service: service,
    role: role,
    variables: variables,
    gatewayCaPem: pem,
    numCores: numCores,
    memSize: memSize,
    diskSpace: diskSpace,
  );
}
