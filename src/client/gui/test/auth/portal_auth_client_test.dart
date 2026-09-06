import 'dart:convert';

import 'package:elp_gui/auth/portal_auth_client.dart';
import 'package:elp_gui/auth/portal_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('PortalAuthClient.login', () {
    test('parses access_token', () async {
      final client = PortalAuthClient(
        httpClient: MockClient((request) async {
          expect(request.url, PortalConfig.userpassUrl);
          expect(jsonDecode(request.body), {
            'username': 'a@b.com',
            'password': 'secret',
          });
          return http.Response(
            jsonEncode({
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final tokens =
          await client.login(username: 'a@b.com', password: 'secret');
      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
      client.close();
    });

    test('accepts legacy authz_token', () async {
      final client = PortalAuthClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'authz_token': 'legacy-access'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final tokens =
          await client.login(username: 'a@b.com', password: 'secret');
      expect(tokens.accessToken, 'legacy-access');
      expect(tokens.refreshToken, isNull);
      client.close();
    });

    test('throws on HTTP error', () async {
      final client = PortalAuthClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'detail': 'Invalid email or password.'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(
        () => client.login(username: 'a@b.com', password: 'bad'),
        throwsA(
          isA<PortalAuthException>().having(
            (e) => e.message,
            'message',
            'Invalid email or password.',
          ),
        ),
      );
      client.close();
    });
    test('parses nested detail.error_msg', () async {
      final client = PortalAuthClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'detail': {
                'error_msg': 'Invalid credentials: email or password not valid',
                'error_code': 'CLIENT',
              },
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(
        () => client.login(username: 'a@b.com', password: 'bad'),
        throwsA(
          isA<PortalAuthException>().having(
            (e) => e.message,
            'message',
            'Invalid credentials: email or password not valid',
          ),
        ),
      );
      client.close();
    });
  });

  group('PortalAuthClient.refresh', () {
    test('posts refresh_token and returns new access', () async {
      final client = PortalAuthClient(
        httpClient: MockClient((request) async {
          expect(request.url, PortalConfig.refreshUrl);
          expect(jsonDecode(request.body), {'refresh_token': 'r1'});
          return http.Response(
            jsonEncode({
              'access_token': 'access-2',
              'refresh_token': 'refresh-2',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final tokens = await client.refresh('r1');
      expect(tokens.accessToken, 'access-2');
      expect(tokens.refreshToken, 'refresh-2');
      client.close();
    });
  });
}
