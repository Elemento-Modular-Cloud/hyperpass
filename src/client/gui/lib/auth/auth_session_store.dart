import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const staySignedInPrefsKey = 'portal_stay_signed_in';

/// Key/value vault for Portal session secrets.
abstract class TokenVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterTokenVault implements TokenVault {
  FlutterTokenVault([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // Desktop apps typically use the file-based keychain, not the
              // data-protection keychain (which needs extra macOS setup).
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryTokenVault implements TokenVault {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// Persists Portal session secrets and the stay-signed-in preference.
class AuthSessionStore {
  AuthSessionStore({
    required SharedPreferences prefs,
    TokenVault? vault,
  })  : _prefs = prefs,
        _vault = vault ?? FlutterTokenVault();

  static const accessKey = 'portal_access_token';
  static const refreshKey = 'portal_refresh_token';
  static const usernameKey = 'portal_username';
  static const passwordKey = 'portal_password';

  final SharedPreferences _prefs;
  final TokenVault _vault;

  bool get staySignedIn => _prefs.getBool(staySignedInPrefsKey) ?? true;

  Future<void> setStaySignedIn(bool value) async {
    await _prefs.setBool(staySignedInPrefsKey, value);
  }

  Future<String?> readAccessToken() => _vault.read(accessKey);
  Future<String?> readRefreshToken() => _vault.read(refreshKey);
  Future<String?> readUsername() => _vault.read(usernameKey);
  Future<String?> readPassword() => _vault.read(passwordKey);

  Future<void> saveSession({
    required String username,
    required String accessToken,
    String? refreshToken,
    String? password,
    required bool staySignedIn,
  }) async {
    await setStaySignedIn(staySignedIn);
    await _vault.write(usernameKey, username);
    await _vault.write(accessKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _vault.write(refreshKey, refreshToken);
    }
    if (staySignedIn && password != null && password.isNotEmpty) {
      await _vault.write(passwordKey, password);
    } else {
      await _vault.delete(passwordKey);
    }
  }

  Future<void> updateTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _vault.write(accessKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _vault.write(refreshKey, refreshToken);
    }
  }

  Future<void> clear() async {
    await Future.wait([
      _vault.delete(accessKey),
      _vault.delete(refreshKey),
      _vault.delete(usernameKey),
      _vault.delete(passwordKey),
    ]);
  }
}
