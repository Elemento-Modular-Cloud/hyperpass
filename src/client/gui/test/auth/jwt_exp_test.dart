import 'dart:convert';

import 'package:elp_gui/auth/jwt_exp.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwtWithExp(int exp) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
  return '$header.$payload.sig';
}

void main() {
  group('jwtExpUnix', () {
    test('reads exp from payload', () {
      expect(jwtExpUnix(_jwtWithExp(1700000000)), 1700000000);
    });

    test('returns null for malformed token', () {
      expect(jwtExpUnix('not-a-jwt'), isNull);
      expect(jwtExpUnix(''), isNull);
    });
  });

  group('jwtShouldRefresh', () {
    test('true when within skew of expiry', () {
      final now = DateTime.utc(2024, 1, 1, 12);
      final exp = now.millisecondsSinceEpoch ~/ 1000 + 30;
      expect(
        jwtShouldRefresh(
          _jwtWithExp(exp),
          skewSeconds: 60,
          now: now,
        ),
        isTrue,
      );
    });

    test('false when expiry is beyond skew', () {
      final now = DateTime.utc(2024, 1, 1, 12);
      final exp = now.millisecondsSinceEpoch ~/ 1000 + 600;
      expect(
        jwtShouldRefresh(
          _jwtWithExp(exp),
          skewSeconds: 60,
          now: now,
        ),
        isFalse,
      );
    });

    test('true for null or empty token', () {
      expect(jwtShouldRefresh(null, skewSeconds: 60), isTrue);
      expect(jwtShouldRefresh('', skewSeconds: 60), isTrue);
    });
  });
}
