sealed class AuthState {
  const AuthState();
}

final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.message});

  final String? message;
}

final class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.username);

  final String username;
}

final class AuthError extends AuthState {
  const AuthError(this.message);

  final String message;
}
