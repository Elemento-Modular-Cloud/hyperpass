import 'dart:io';

/// Live Elemento Spacedock gate. Override the base with `ELP_SPACEDOCK_URL`
/// (e.g. `http://127.0.0.1:8080` for a local replica).
abstract final class SpacedockConfig {
  static const defaultBase = 'https://spacedock.elemento.cloud';
  static const marketplaceBundlePath = '/v1/marketplace/bundle';
  static const imagesBundlePath = '/v1/images/bundle';
  static const tokenSettingKey = 'local.spacedock.token';
  static const urlEnvVar = 'ELP_SPACEDOCK_URL';

  static String baseUrl([Map<String, String>? environment]) {
    final raw = (environment ?? Platform.environment)[urlEnvVar]?.trim();
    if (raw == null || raw.isEmpty) return defaultBase;
    return raw.replaceFirst(RegExp(r'/+$'), '');
  }

  static String marketplaceBundleUrl([Map<String, String>? environment]) =>
      '${baseUrl(environment)}$marketplaceBundlePath';

  static String imagesBundleUrl([Map<String, String>? environment]) =>
      '${baseUrl(environment)}$imagesBundlePath';
}
