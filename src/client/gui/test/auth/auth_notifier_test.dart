import 'dart:convert';

import 'package:elp_gui/auth/auth_provider.dart';
import 'package:elp_gui/auth/auth_session_store.dart';
import 'package:elp_gui/auth/auth_state.dart';
import 'package:elp_gui/auth/portal_auth_client.dart';
import 'package:elp_gui/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwtWithExp(int exp) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
  return '$header.$payload.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late MemoryTokenVault vault;
  late AuthSessionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    vault = MemoryTokenVault();
    store = AuthSessionStore(prefs: prefs, vault: vault);
  });

  ProviderContainer makeContainer(http.Client httpClient) {
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authSessionStoreProvider.overrideWithValue(store),
        portalAuthClientProvider.overrideWithValue(
          PortalAuthClient(httpClient: httpClient),
        ),
      ],
    );
  }

  test('bootstrap authenticates when access token is still valid', () async {
    final exp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600;
    await store.saveSession(
      username: 'user@elemento.cloud',
      accessToken: _jwtWithExp(exp),
      refreshToken: 'refresh',
      password: 'pw',
      staySignedIn: true,
    );

    final container = makeContainer(
      MockClient((_) async => http.Response('unexpected', 500)),
    );
    addTearDown(container.dispose);

    // Trigger build + bootstrap.
    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(authProvider);
    expect(state, isA<AuthAuthenticated>());
    expect((state as AuthAuthenticated).username, 'user@elemento.cloud');
  });

  test('bootstrap refreshes expired access token', () async {
    final exp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 10;
    await store.saveSession(
      username: 'user@elemento.cloud',
      accessToken: _jwtWithExp(exp),
      refreshToken: 'refresh-old',
      password: 'pw',
      staySignedIn: true,
    );

    final freshExp =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600;
    final container = makeContainer(
      MockClient((request) async {
        expect(request.url.path, contains('/auth/refresh'));
        return http.Response(
          jsonEncode({
            'access_token': _jwtWithExp(freshExp),
            'refresh_token': 'refresh-new',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(container.dispose);

    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(authProvider), isA<AuthAuthenticated>());
    expect(await store.readRefreshToken(), 'refresh-new');
  });

  test('bootstrap falls back to userpass when refresh fails', () async {
    final exp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 10;
    await store.saveSession(
      username: 'user@elemento.cloud',
      accessToken: _jwtWithExp(exp),
      refreshToken: 'bad-refresh',
      password: 'pw',
      staySignedIn: true,
    );

    final freshExp =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600;
    var calls = 0;
    final container = makeContainer(
      MockClient((request) async {
        calls++;
        if (request.url.path.contains('/auth/refresh')) {
          return http.Response('nope', 401);
        }
        expect(request.url.path, contains('/auth/userpass'));
        return http.Response(
          jsonEncode({
            'access_token': _jwtWithExp(freshExp),
            'refresh_token': 'refresh-from-login',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(container.dispose);

    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(authProvider), isA<AuthAuthenticated>());
    expect(calls, greaterThanOrEqualTo(2));
    expect(await store.readRefreshToken(), 'refresh-from-login');
  });

  test('bootstrap clears and shows login when restore fails', () async {
    final exp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 10;
    await store.saveSession(
      username: 'user@elemento.cloud',
      accessToken: _jwtWithExp(exp),
      refreshToken: 'bad-refresh',
      password: 'bad-pw',
      staySignedIn: true,
    );

    final container = makeContainer(
      MockClient((_) async => http.Response('nope', 401)),
    );
    addTearDown(container.dispose);

    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(authProvider), isA<AuthUnauthenticated>());
    expect(await store.readAccessToken(), isNull);
  });

  test('login and logout round-trip', () async {
    final freshExp =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600;
    final container = makeContainer(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': _jwtWithExp(freshExp),
            'refresh_token': 'r1',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(container.dispose);

    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container.read(authProvider.notifier).login(
          username: 'user@elemento.cloud',
          password: 'secret',
          staySignedIn: true,
        );

    expect(container.read(authProvider), isA<AuthAuthenticated>());
    expect(await store.readPassword(), 'secret');

    await container.read(authProvider.notifier).logout();
    expect(container.read(authProvider), isA<AuthUnauthenticated>());
    expect(await store.readAccessToken(), isNull);
    expect(await store.readPassword(), isNull);
  });
}
