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
