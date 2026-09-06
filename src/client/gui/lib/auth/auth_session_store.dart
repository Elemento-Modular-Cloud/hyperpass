import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logger.dart';

const staySignedInPrefsKey = 'portal_stay_signed_in';
const guestModePrefsKey = 'portal_guest_mode';

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

/// SharedPreferences-backed vault used when Keychain entitlements are missing
/// (common for ad-hoc / unsigned macOS desktop builds).
class PrefsTokenVault implements TokenVault {
  PrefsTokenVault(this._prefs);

  static const _prefix = 'portal_secret_';

  final SharedPreferences _prefs;

  String _k(String key) => '$_prefix$key';

  @override
  Future<String?> read(String key) async => _prefs.getString(_k(key));

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(_k(key), value);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(_k(key));
  }
}

/// Tries Keychain first; on entitlement / platform failures falls back to prefs.
class ResilientTokenVault implements TokenVault {
  ResilientTokenVault({
    required SharedPreferences prefs,
    TokenVault? primary,
    TokenVault? fallback,
  })  : _primary = primary ?? FlutterTokenVault(),
        _fallback = fallback ?? PrefsTokenVault(prefs);

  final TokenVault _primary;
  final TokenVault _fallback;
  var _useFallback = false;

  bool get usingFallback => _useFallback;

  Future<T> _withFallback<T>(
    Future<T> Function(TokenVault vault) action, {
    required T Function() onBothFailed,
  }) async {
    if (!_useFallback) {
      try {
        return await action(_primary);
      } on PlatformException catch (e, st) {
        logger.w(
          'Keychain unavailable (${e.code}); using prefs session store',
          error: e,
          stackTrace: st,
        );
        _useFallback = true;
      } catch (e, st) {
        logger.w(
          'Keychain unavailable; using prefs session store',
          error: e,
          stackTrace: st,
        );
        _useFallback = true;
      }
    }
    try {
      return await action(_fallback);
    } catch (e, st) {
      logger.e('Prefs session store failed', error: e, stackTrace: st);
      return onBothFailed();
    }
  }

  @override
  Future<String?> read(String key) => _withFallback(
        (vault) => vault.read(key),
        onBothFailed: () => null,
      );

  @override
  Future<void> write(String key, String value) => _withFallback(
        (vault) => vault.write(key, value),
        onBothFailed: () {},
      );

  @override
  Future<void> delete(String key) => _withFallback(
        (vault) => vault.delete(key),
        onBothFailed: () {},
      );
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
        _vault = vault ?? ResilientTokenVault(prefs: prefs);

  static const accessKey = 'portal_access_token';
  static const refreshKey = 'portal_refresh_token';
  static const usernameKey = 'portal_username';
  static const passwordKey = 'portal_password';

  final SharedPreferences _prefs;
  final TokenVault _vault;

  bool get staySignedIn => _prefs.getBool(staySignedInPrefsKey) ?? true;

  bool get guestMode => _prefs.getBool(guestModePrefsKey) ?? false;

  Future<void> setStaySignedIn(bool value) async {
    await _prefs.setBool(staySignedInPrefsKey, value);
  }

  Future<void> setGuestMode(bool value) async {
    await _prefs.setBool(guestModePrefsKey, value);
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
    await setGuestMode(false);
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
