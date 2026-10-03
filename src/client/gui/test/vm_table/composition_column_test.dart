import 'package:elp_gui/daemon_source.dart';
import 'package:elp_gui/grpc_client.dart';
import 'package:elp_gui/services/service_instance_headers.dart';
import 'package:elp_gui/vm_table/group_by_intent.dart';
import 'package:elp_gui/vm_table/vm_table_headers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VM table includes a composition column after the shell', () {
    expect(
      headers.map((h) => h.name),
      containsAll(['NAME', 'SHELL', 'COMPOSITION', 'STATE']),
    );
    final composition = headers.firstWhere((h) => h.name == 'COMPOSITION');
    final info = TaggedVmInfo(
      id: elpVm('web-redis'),
      info: DetailedInfoItem(
        name: 'web-redis',
        intent: 'web',
        intentRole: 'redis',
      ),
    );
    expect(composition.sortKey!(info), 'web');
  });

  test('services table includes a composition column', () {
    expect(
      serviceInstanceHeaders.map((h) => h.name),
      containsAll(['NAME', 'SHELL', 'COMPOSITION', 'SERVICE']),
    );
  });

  test('composition cells show name, role, or an em dash', () {
    expect(compositionColumnLabel(intent: '', role: 'redis'), '—');
    expect(
      compositionColumnLabel(intent: 'lab', role: 'qdrant'),
      'lab · qdrant',
    );
  });
}
