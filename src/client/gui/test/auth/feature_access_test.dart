import 'package:elp_gui/auth/auth_provider.dart';
import 'package:elp_gui/auth/auth_session_store.dart';
import 'package:elp_gui/auth/auth_state.dart';
import 'package:elp_gui/auth/feature_access.dart';
import 'package:elp_gui/auth/portal_auth_client.dart';
import 'package:elp_gui/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AuthSessionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = AuthSessionStore(prefs: prefs, vault: MemoryTokenVault());
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authSessionStoreProvider.overrideWithValue(store),
        portalAuthClientProvider.overrideWithValue(
          PortalAuthClient(
            httpClient: MockClient((_) async => http.Response('nope', 500)),
          ),
        ),
      ],
    );
  }

  test('continueAsGuest unlocks app with limited feature access', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    container.read(authProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container.read(authProvider.notifier).continueAsGuest();

    expect(container.read(authProvider), isA<AuthGuest>());
    expect(store.guestMode, isTrue);

    final access = container.read(featureAccessProvider);
    expect(access.guest, isTrue);
    expect(access.hasFullProductAccess, isFalse);
    expect(access.canUseLlms, isFalse);
    expect(access.canUseServices, isFalse);
    expect(access.ubuntuImagesOnly, isTrue);
  });

  test('signed-in accounts retain full feature access', () {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authProvider.overrideWith(
            () => _FixedAuthNotifier(const AuthAuthenticated('a@b.com'))),
      ],
    );
    addTearDown(container.dispose);

    final access = container.read(featureAccessProvider);
    expect(access.signedIn, isTrue);
    expect(access.hasFullProductAccess, isTrue);
    expect(access.canUseLlms, isTrue);
    expect(access.canUseServices, isTrue);
    expect(access.ubuntuImagesOnly, isFalse);
  });
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}
