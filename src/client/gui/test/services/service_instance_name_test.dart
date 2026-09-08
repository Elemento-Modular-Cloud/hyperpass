import 'package:elp_gui/services/service_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated names open with a hostname-safe lowercase service id', () {
    expect(serviceInstanceNamePrefix('openwebui_v1'), 'openwebui-v1');
    expect(serviceInstanceNamePrefix('n8n_v3'), 'n8n-v3');
    expect(serviceInstanceNamePrefix('n8n_runner_v1'), 'n8n-runner-v1');
    expect(serviceInstanceNamePrefix('Qdrant_V1'), 'qdrant-v1');
  });

  test('prefixes the petname with the service model', () {
    expect(
      prefixedServiceInstanceName('openwebui_v1', 'witty-fox'),
      'openwebui-v1-witty-fox',
    );
    expect(prefixedServiceInstanceName('postgres_v2', ''), 'postgres-v2');
    expect(prefixedServiceInstanceName('', 'witty-fox'), 'witty-fox');
  });
}
