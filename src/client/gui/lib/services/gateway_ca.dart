import 'dart:convert';
import 'dart:io';

/// Host-local CA export for embedding into guest cloud-init.
const gatewayCaUrl = 'https://127.0.0.1:7777/ca.crt';

/// Ubuntu path written by service cloud-init so `update-ca-certificates` picks it up.
const gatewayCaGuestPath = '/usr/local/share/ca-certificates/elp-llm-gateway.crt';

const gatewayCaUpdateRuncmd = 'update-ca-certificates';

bool looksLikePemCertificate(String pem) => pem.contains('BEGIN CERTIFICATE');

/// GET [gatewayCaUrl] (or [uri]), accepting the localhost self-signed leaf.
Future<String> fetchGatewayCaPem({
  Uri? uri,
  HttpClient? client,
}) async {
  final target = uri ?? Uri.parse(gatewayCaUrl);
  final ownsClient = client == null;
  final http = client ??
      (HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (cert, host, port) =>
            host == '127.0.0.1' || host == 'localhost');

  try {
    final request = await http.getUrl(target);
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw StateError(
        'GET $target returned HTTP ${response.statusCode}',
      );
    }
    if (!looksLikePemCertificate(body)) {
      throw StateError('GET $target did not return a PEM certificate');
    }
    return body;
  } finally {
    if (ownsClient) http.close(force: true);
  }
}
