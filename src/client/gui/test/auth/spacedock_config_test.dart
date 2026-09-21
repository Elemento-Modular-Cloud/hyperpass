import 'package:elp_gui/auth/spacedock_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to the live Spacedock host', () {
    expect(SpacedockConfig.baseUrl(const {}),
        'https://spacedock.elemento.cloud');
    expect(
      SpacedockConfig.marketplaceBundleUrl(const {}),
      'https://spacedock.elemento.cloud/v1/marketplace/bundle',
    );
    expect(
      SpacedockConfig.imagesBundleUrl(const {}),
      'https://spacedock.elemento.cloud/v1/images/bundle',
    );
  });

  test('strips a trailing slash from ELP_SPACEDOCK_URL', () {
    const env = {'ELP_SPACEDOCK_URL': 'http://127.0.0.1:8080/'};
    expect(SpacedockConfig.baseUrl(env), 'http://127.0.0.1:8080');
    expect(
      SpacedockConfig.marketplaceBundleUrl(env),
      'http://127.0.0.1:8080/v1/marketplace/bundle',
    );
  });
}
