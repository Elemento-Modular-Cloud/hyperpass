import 'package:flutter_test/flutter_test.dart';
import 'package:elp_gui/daemon_source.dart';
import 'package:elp_gui/grpc_client.dart';

void main() {
  group('VmId / sidebar keys', () {
    test('encodes and parses Electros LaunchPad keys', () {
      final id = elpVm('foo-bar');
      expect(id.sidebarKey, 'vm-elp-foo-bar');
      expect(parseSidebarVmKey(id.sidebarKey), id);
    });

    test('encodes and parses Multipass keys', () {
      final id = multipassVm('foo-bar');
      expect(id.sidebarKey, 'vm-multipass-foo-bar');
      expect(parseSidebarVmKey(id.sidebarKey), id);
    });

    test('legacy vm-name keys map to Electros LaunchPad', () {
      expect(
        parseSidebarVmKey('vm-legacy-name'),
        elpVm('legacy-name'),
      );
    });

    test('same name different sources are distinct', () {
      final a = elpVm('foo');
      final b = multipassVm('foo');
      expect(a == b, isFalse);
      expect({a, b}.length, 2);
    });
  });

  group('TaggedVmInfo merge ordering', () {
    test('sorts by name then Electros LaunchPad before Multipass', () {
      final tagged = [
        TaggedVmInfo(
          id: multipassVm('beta'),
          info: DetailedInfoItem(name: 'beta'),
        ),
        TaggedVmInfo(
          id: elpVm('alpha'),
          info: DetailedInfoItem(name: 'alpha'),
        ),
        TaggedVmInfo(
          id: multipassVm('alpha'),
          info: DetailedInfoItem(name: 'alpha'),
        ),
        TaggedVmInfo(
          id: elpVm('beta'),
          info: DetailedInfoItem(name: 'beta'),
        ),
      ]..sort((a, b) {
          final byName = a.name.compareTo(b.name);
          if (byName != 0) return byName;
          return a.source.index.compareTo(b.source.index);
        });

      expect(tagged.map((t) => '${t.source.name}:${t.name}').toList(), [
        'elp:alpha',
        'multipass:alpha',
        'elp:beta',
        'multipass:beta',
      ]);
    });
  });
}
