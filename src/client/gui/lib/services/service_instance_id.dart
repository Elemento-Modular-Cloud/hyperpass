import '../daemon_source.dart';

const serviceInstancesSidebarKey = 'service-instances';

const _serviceInstancePrefix = 'service-instance-';

String serviceInstanceSidebarKey(String instanceName) =>
    '$_serviceInstancePrefix${Uri.encodeComponent(instanceName)}';

String? parseServiceInstanceSidebarKey(String key) {
  if (key == serviceInstancesSidebarKey) return null;
  if (!key.startsWith(_serviceInstancePrefix)) return null;
  final encoded = key.substring(_serviceInstancePrefix.length);
  if (encoded.isEmpty) return null;
  return Uri.decodeComponent(encoded);
}

VmId? serviceInstanceVmId(String key) {
  final name = parseServiceInstanceSidebarKey(key);
  if (name == null) return null;
  return hyperpassVm(name);
}
