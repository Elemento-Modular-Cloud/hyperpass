import 'dart:convert';

import 'package:elp_gui/auth/jwt_exp.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwtWithExp(Object exp) {
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

    test('reads string exp claims', () {
      expect(jwtExpUnix(_jwtWithExp('1700000000')), 1700000000);
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

    test('true when exp is already in the past', () {
      final now = DateTime.utc(2024, 1, 1, 12);
      final exp = now.millisecondsSinceEpoch ~/ 1000 - 10;
      expect(
        jwtShouldRefresh(
          _jwtWithExp(exp),
          skewSeconds: 60,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('jwtRefreshDelay', () {
    test('zero when exp is in the past or inside skew', () {
      final now = DateTime.utc(2024, 1, 1, 12);
      final past = now.millisecondsSinceEpoch ~/ 1000 - 10;
      final insideSkew = now.millisecondsSinceEpoch ~/ 1000 + 30;
      expect(
        jwtRefreshDelay(_jwtWithExp(past), skewSeconds: 60, now: now),
        Duration.zero,
      );
      expect(
        jwtRefreshDelay(_jwtWithExp(insideSkew), skewSeconds: 60, now: now),
        Duration.zero,
      );
      expect(jwtRefreshDelay(null, skewSeconds: 60, now: now), Duration.zero);
    });

    test('positive when expiry is beyond skew', () {
      final now = DateTime.utc(2024, 1, 1, 12);
      final exp = now.millisecondsSinceEpoch ~/ 1000 + 600;
      expect(
        jwtRefreshDelay(_jwtWithExp(exp), skewSeconds: 60, now: now),
        const Duration(seconds: 540),
      );
    });
  });
}
