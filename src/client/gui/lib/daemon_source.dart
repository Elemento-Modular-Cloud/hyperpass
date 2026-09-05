enum DaemonSource {
  elp,
  multipass;

  String get label => switch (this) {
        DaemonSource.elp => 'Electros LaunchPad',
        DaemonSource.multipass => 'Multipass',
      };
}

typedef VmId = ({DaemonSource source, String name});

extension VmIdX on VmId {
  String get sidebarKey => 'vm-${source.name}-$name';

  String get displayLabel => switch (source) {
        DaemonSource.elp => name,
        DaemonSource.multipass => '$name (Multipass)',
      };
}

VmId elpVm(String name) => (source: DaemonSource.elp, name: name);

VmId multipassVm(String name) => (source: DaemonSource.multipass, name: name);

VmId? parseSidebarVmKey(String key) {
  if (!key.startsWith('vm-')) return null;
  final rest = key.substring(3);
  for (final source in DaemonSource.values) {
    final prefix = '${source.name}-';
    if (rest.startsWith(prefix)) {
      final name = rest.substring(prefix.length);
      if (name.isEmpty) return null;
      return (source: source, name: name);
    }
  }
  // Legacy keys from before dual-daemon: treat as Electros LaunchPad.
  if (rest.isEmpty) return null;
  return elpVm(rest);
}
