/// Fixed Elemento Portal endpoints for Hyperpass account auth (prod only).
abstract final class PortalConfig {
  static const portalBase = 'https://portal.elemento.cloud';
  static const userpassPath = '/api/v2/auth/userpass';
  static const refreshPath = '/api/v2/auth/refresh';
  static const passwordRecoveryPath = '/password_recovery';

  /// Refresh access token this many seconds before JWT `exp`.
  static const refreshSkewSeconds = 60;

  static Uri get userpassUrl => Uri.parse('$portalBase$userpassPath');
  static Uri get refreshUrl => Uri.parse('$portalBase$refreshPath');
  static Uri get passwordRecoveryUrl =>
      Uri.parse('$portalBase$passwordRecoveryPath');
}
