import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpass_gui/daemon_source.dart';
import 'package:hyperpass_gui/grpc_client.dart';

void main() {
  group('VmId / sidebar keys', () {
    test('encodes and parses Hyperpass keys', () {
      final id = hyperpassVm('foo-bar');
      expect(id.sidebarKey, 'vm-hyperpass-foo-bar');
      expect(parseSidebarVmKey(id.sidebarKey), id);
    });

    test('encodes and parses Multipass keys', () {
      final id = multipassVm('foo-bar');
      expect(id.sidebarKey, 'vm-multipass-foo-bar');
      expect(parseSidebarVmKey(id.sidebarKey), id);
    });

    test('legacy vm-name keys map to Hyperpass', () {
      expect(
        parseSidebarVmKey('vm-legacy-name'),
        hyperpassVm('legacy-name'),
      );
    });

    test('same name different sources are distinct', () {
      final a = hyperpassVm('foo');
      final b = multipassVm('foo');
      expect(a == b, isFalse);
      expect({a, b}.length, 2);
    });
  });

  group('TaggedVmInfo merge ordering', () {
    test('sorts by name then Hyperpass before Multipass', () {
      final tagged = [
        TaggedVmInfo(
          id: multipassVm('beta'),
          info: DetailedInfoItem(name: 'beta'),
        ),
        TaggedVmInfo(
          id: hyperpassVm('alpha'),
          info: DetailedInfoItem(name: 'alpha'),
        ),
        TaggedVmInfo(
          id: multipassVm('alpha'),
          info: DetailedInfoItem(name: 'alpha'),
        ),
        TaggedVmInfo(
          id: hyperpassVm('beta'),
          info: DetailedInfoItem(name: 'beta'),
        ),
      ]..sort((a, b) {
          final byName = a.name.compareTo(b.name);
          if (byName != 0) return byName;
          return a.source.index.compareTo(b.source.index);
        });

      expect(tagged.map((t) => '${t.source.name}:${t.name}').toList(), [
        'hyperpass:alpha',
        'multipass:alpha',
        'hyperpass:beta',
        'multipass:beta',
      ]);
    });
  });
}
