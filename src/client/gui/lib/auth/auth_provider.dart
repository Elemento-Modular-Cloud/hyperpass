import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synchronized/synchronized.dart';

import '../logger.dart';
import '../providers.dart';
import 'auth_session_store.dart';
import 'auth_state.dart';
import 'jwt_exp.dart';
import 'portal_auth_client.dart';
import 'portal_config.dart';

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  return AuthSessionStore(prefs: ref.watch(sharedPreferencesProvider));
});

final portalAuthClientProvider = Provider<PortalAuthClient>((ref) {
  final client = PortalAuthClient();
  ref.onDispose(client.close);
  return client;
});

final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  final _tokenLock = Lock();

  AuthSessionStore get _store => ref.read(authSessionStoreProvider);
  PortalAuthClient get _client => ref.read(portalAuthClientProvider);

  @override
  AuthState build() {
    Future.microtask(_bootstrap);
    return const AuthUnknown();
  }

  Future<void> _bootstrap() async {
    try {
      final access = await _store.readAccessToken();
      final refresh = await _store.readRefreshToken();
      final username = await _store.readUsername();

      if (access == null ||
          access.isEmpty ||
          username == null ||
          username.isEmpty) {
        if (_store.guestMode) {
          state = const AuthGuest();
        } else {
          state = const AuthUnauthenticated();
        }
        return;
      }

      if (!jwtShouldRefresh(
        access,
        skewSeconds: PortalConfig.refreshSkewSeconds,
      )) {
        await _store.setGuestMode(false);
        state = AuthAuthenticated(username);
        return;
      }

      final restored = await _restoreSession(
        username: username,
        refreshToken: refresh,
      );
      if (!restored) {
        await _store.clear();
        if (_store.guestMode) {
          state = const AuthGuest();
        } else {
          state = const AuthUnauthenticated();
        }
      }
    } catch (_) {
      await _store.clear();
      state = const AuthUnauthenticated();
    }
  }

  Future<bool> _restoreSession({
    required String username,
    String? refreshToken,
  }) async {
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final tokens = await _client.refresh(refreshToken);
        await _store.updateTokens(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken ?? refreshToken,
        );
        await _store.setGuestMode(false);
        state = AuthAuthenticated(username);
        return true;
      } catch (_) {
        // Fall through to stay-signed userpass.
      }
    }

    if (!_store.staySignedIn) return false;
    final password = await _store.readPassword();
    if (password == null || password.isEmpty) return false;

    try {
      final tokens =
          await _client.login(username: username, password: password);
      await _store.saveSession(
        username: username,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        password: password,
        staySignedIn: true,
      );
      state = AuthAuthenticated(username);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> login({
    required String username,
    required String password,
    required bool staySignedIn,
  }) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty || password.isEmpty) {
      state = const AuthError('Email and password are required.');
      return;
    }

    state = const AuthAuthenticating();
    try {
      final tokens = await _client.login(username: trimmed, password: password);
      await _store.saveSession(
        username: trimmed,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        password: password,
        staySignedIn: staySignedIn,
      );
      state = AuthAuthenticated(trimmed);
    } on PortalAuthException catch (e) {
      logger.w('Portal login rejected', error: e);
      state = AuthError(e.message);
    } catch (e, st) {
      logger.e('Portal login failed', error: e, stackTrace: st);
      state = AuthError(_friendlyFailure(e));
    }
  }

  String _friendlyFailure(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('connection') ||
        text.contains('network') ||
        text.contains('timed out') ||
        text.contains('timeout')) {
      return 'Unable to reach Elemento Portal. Check your connection and try again.';
    }
    if (text.contains('secure_storage') ||
        text.contains('keychain') ||
        text.contains('unexpected security result')) {
      return 'Signed in, but saving the session failed. Check Keychain access for Electros LaunchPad.';
    }
    return 'Unable to sign in (${error.runtimeType}). See logs for details.';
  }

  Future<void> continueAsGuest() async {
    await _store.setGuestMode(true);
    try {
      await _store.clear();
    } catch (e, st) {
      logger.w('Could not clear session secrets for guest mode',
          error: e, stackTrace: st);
    }
    state = const AuthGuest();
  }

  /// Leave guest mode and show the Portal login form.
  Future<void> requestSignIn() async {
    await _store.setGuestMode(false);
    state = const AuthUnauthenticated();
  }

  Future<void> logout() async {
    await _store.setGuestMode(false);
    try {
      await _store.clear();
    } catch (e, st) {
      logger.w('Could not clear session secrets on logout',
          error: e, stackTrace: st);
    }
    state = const AuthUnauthenticated();
  }

  /// Returns a usable access token, refreshing (or re-logging in) if needed.
  Future<String> requireAccessToken() {
    return _tokenLock.synchronized(() async {
      final access = await _store.readAccessToken();
      final username = await _store.readUsername();
      if (username == null || username.isEmpty) {
        throw PortalAuthException('Not signed in.');
      }

      if (!jwtShouldRefresh(
        access,
        skewSeconds: PortalConfig.refreshSkewSeconds,
      )) {
        return access!;
      }

      final refresh = await _store.readRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        try {
          final tokens = await _client.refresh(refresh);
          await _store.updateTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken ?? refresh,
          );
          return tokens.accessToken;
        } catch (_) {
          // Fall through to stay-signed userpass.
        }
      }

      if (_store.staySignedIn) {
        final password = await _store.readPassword();
        if (password != null && password.isNotEmpty) {
          final tokens =
              await _client.login(username: username, password: password);
          await _store.saveSession(
            username: username,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            password: password,
            staySignedIn: true,
          );
          return tokens.accessToken;
        }
      }

      await _store.clear();
      state = const AuthUnauthenticated(
        message: 'Your session expired. Please sign in again.',
      );
      throw PortalAuthException('Session expired.');
    });
  }
}
