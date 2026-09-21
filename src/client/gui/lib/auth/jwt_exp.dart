import 'dart:convert';

/// Decode JWT `exp` (unix seconds) without verifying the signature.
int? jwtExpUnix(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)))
        as Map<String, dynamic>;
    final exp = payload['exp'];
    if (exp is int) return exp;
    if (exp is num) return exp.toInt();
    if (exp is String) return int.tryParse(exp);
    return null;
  } catch (_) {
    return null;
  }
}

/// True when [token] is missing, unparsable, or expires within [skewSeconds].
bool jwtShouldRefresh(String? token,
    {required int skewSeconds, DateTime? now}) {
  if (token == null || token.isEmpty) return true;
  final exp = jwtExpUnix(token);
  if (exp == null) return true;
  final current =
      (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
  return exp - current <= skewSeconds;
}

/// Delay until [token] should be refreshed (`exp - skew`).
///
/// [Duration.zero] when the token is missing, unparsable, already expired,
/// or inside the skew window.
Duration jwtRefreshDelay(String? token,
    {required int skewSeconds, DateTime? now}) {
  if (jwtShouldRefresh(token, skewSeconds: skewSeconds, now: now)) {
    return Duration.zero;
  }
  final exp = jwtExpUnix(token!);
  final current =
      (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
  return Duration(seconds: exp! - current - skewSeconds);
}
