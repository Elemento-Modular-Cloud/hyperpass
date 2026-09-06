import 'package:flutter/material.dart' hide Switch;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_background.dart';
import '../brand.dart';
import '../catalogue/catalogue_surface.dart';
import '../l10n/app_localizations.dart';
import '../switch.dart';
import 'auth_provider.dart';
import 'auth_state.dart';
import 'portal_config.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _staySignedIn = true;
  var _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _errorMessage(AuthState auth) {
    return switch (auth) {
      AuthError(:final message) => message,
      AuthUnauthenticated(:final message) => message,
      _ => null,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      // Keep UI local validation without going through the notifier.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginRequiredFields)),
      );
      return;
    }
    await ref.read(authProvider.notifier).login(
          username: email,
          password: password,
          staySignedIn: _staySignedIn,
        );
  }

  Future<void> _openPasswordRecovery() async {
    final uri = PortalConfig.passwordRecoveryUrl;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final busy = auth is AuthAuthenticating;
    final error = _errorMessage(auth);
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        const AppBackground(),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: CatalogueSurface(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      Brand.appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.loginTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _emailController,
                      enabled: !busy,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.loginEmailLabel,
                      ),
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      enabled: !busy,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.loginPasswordLabel,
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: busy
                              ? null
                              : () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!busy) _submit();
                      },
                    ),
                    const SizedBox(height: 16),
                    Switch(
                      label: l10n.loginStaySignedIn,
                      value: _staySignedIn,
                      trailingSwitch: true,
                      enabled: !busy,
                      onChanged: (value) =>
                          setState(() => _staySignedIn = value),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        error,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: busy ? null : _submit,
                      child:
                          Text(busy ? l10n.loginSigningIn : l10n.loginSignIn),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy ? null : _openPasswordRecovery,
                      child: Text(l10n.loginForgotPassword),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
