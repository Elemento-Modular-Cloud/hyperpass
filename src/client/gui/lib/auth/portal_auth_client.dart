import 'dart:convert';

import 'package:http/http.dart' as http;

import 'portal_config.dart';

class PortalAuthTokens {
  const PortalAuthTokens({
    required this.accessToken,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
}

class PortalAuthException implements Exception {
  PortalAuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Direct Elemento Portal auth (userpass + refresh). No local auth daemon.
class PortalAuthClient {
  PortalAuthClient({http.Client? httpClient, Duration? requestTimeout})
      : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        requestTimeout = requestTimeout ?? defaultRequestTimeout;

  static const defaultRequestTimeout = Duration(seconds: 8);

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<http.Response> _post(Uri url, Object body, String action) {
    return _client
        .post(
          url,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(
          requestTimeout,
          onTimeout: () => throw PortalAuthException(
            'Portal $action timed out.',
          ),
        );
  }

  Future<PortalAuthTokens> login({
    required String username,
    required String password,
  }) async {
    final response = await _post(
      PortalConfig.userpassUrl,
      {
        'username': username,
        'password': password,
      },
      'login',
    );
    return _parseTokenResponse(response, action: 'login');
  }

  Future<PortalAuthTokens> refresh(String refreshToken) async {
    final response = await _post(
      PortalConfig.refreshUrl,
      {'refresh_token': refreshToken},
      'refresh',
    );
    return _parseTokenResponse(response, action: 'refresh');
  }

  PortalAuthTokens _parseTokenResponse(
    http.Response response, {
    required String action,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PortalAuthException(
        _errorMessage(response, action: action),
        statusCode: response.statusCode,
      );
    }

    late final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Expected JSON object');
      }
      data = decoded;
    } catch (_) {
      throw PortalAuthException(
        'Portal $action returned an invalid response.',
        statusCode: response.statusCode,
      );
    }

    final access = data['access_token'] ?? data['authz_token'];
    if (access is! String || access.isEmpty) {
      throw PortalAuthException(
        'Portal $action response missing access token.',
        statusCode: response.statusCode,
      );
    }

    final refresh = data['refresh_token'];
    return PortalAuthTokens(
      accessToken: access,
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
    );
  }

  String _errorMessage(http.Response response, {required String action}) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail =
            decoded['detail'] ?? decoded['message'] ?? decoded['error'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is Map) {
          final nested =
              detail['error_msg'] ?? detail['message'] ?? detail['error'];
          if (nested is String && nested.isNotEmpty) return nested;
        }
      }
    } catch (_) {}
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'Invalid email or password.';
    }
    return 'Portal $action failed (${response.statusCode}).';
  }
}
