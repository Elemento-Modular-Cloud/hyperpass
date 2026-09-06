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

/// Local-only session without an Elemento Portal account.
final class AuthGuest extends AuthState {
  const AuthGuest();
}

final class AuthError extends AuthState {
  const AuthError(this.message);

  final String message;
}

extension AuthStateX on AuthState {
  bool get canEnterApp => this is AuthAuthenticated || this is AuthGuest;
}
