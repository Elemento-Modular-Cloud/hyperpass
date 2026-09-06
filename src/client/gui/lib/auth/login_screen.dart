import 'dart:ui';

import 'package:flutter/material.dart' hide Switch;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_background.dart';
import '../brand.dart';
import '../l10n/app_localizations.dart';
import '../switch.dart';
import 'auth_provider.dart';
import 'auth_state.dart';
import 'portal_config.dart';

/// Electros-style login: floating frosted form over wallpaper.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  var _staySignedIn = true;
  var _obscurePassword = true;

  static const _noDecoration = TextStyle(
    decoration: TextDecoration.none,
    decorationColor: Colors.transparent,
    decorationThickness: 0,
  );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
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

  InputDecoration _fieldDecoration({
    required String hint,
    required Color onSurface,
    Widget? suffixIcon,
  }) {
    final fill = Colors.white.withValues(alpha: 0.08);
    final radius = BorderRadius.circular(Brand.radius);
    return InputDecoration(
      hintText: hint,
      hintStyle: _noDecoration.copyWith(
        fontFamily: Brand.fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: onSurface.withValues(alpha: 0.5),
      ),
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Brand.accent, width: 1),
      ),
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);
    final busy = auth is AuthAuthenticating;
    final error = _errorMessage(auth);
    final onSurface = Brand.crystalWhite;

    // Kill the app-wide filled TextButton theme and any inherited underlines.
    final base = Theme.of(context);
    final loginTheme = base.copyWith(
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(0),
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
      textTheme: base.textTheme.apply(decoration: TextDecoration.none),
      primaryTextTheme:
          base.primaryTextTheme.apply(decoration: TextDecoration.none),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          borderSide: const BorderSide(color: Brand.accent, width: 1),
        ),
      ),
    );

    return Theme(
      data: loginTheme,
      child: DefaultTextStyle.merge(
        style: _noDecoration,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const AppBackground(),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.05,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    Brand.logoAsset,
                                    width: 34,
                                    height: 34,
                                    colorFilter: const ColorFilter.mode(
                                      Brand.accent,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  BrandAppName(
                                    textAlign: TextAlign.center,
                                    style: _noDecoration.copyWith(
                                      fontFamily: Brand.fontFamily,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: onSurface,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 36),
                              TextField(
                                controller: _emailController,
                                enabled: !busy,
                                autofillHints: const [AutofillHints.email],
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                style: _noDecoration.copyWith(
                                  fontFamily: Brand.fontFamily,
                                  fontSize: 16,
                                  color: onSurface,
                                ),
                                cursorColor: Brand.accent,
                                decoration: _fieldDecoration(
                                  hint: l10n.loginEmailLabel,
                                  onSurface: onSurface,
                                ),
                                onSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                enabled: !busy,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                style: _noDecoration.copyWith(
                                  fontFamily: Brand.fontFamily,
                                  fontSize: 16,
                                  color: onSurface,
                                ),
                                cursorColor: Brand.accent,
                                decoration: _fieldDecoration(
                                  hint: l10n.loginPasswordLabel,
                                  onSurface: onSurface,
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: busy
                                        ? null
                                        : () => setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 20,
                                      color:
                                          onSurface.withValues(alpha: 0.55),
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) {
                                  if (!busy) _submit();
                                },
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _LoginTextAction(
                                  label: l10n.loginForgotPassword,
                                  color: Brand.accent,
                                  enabled: !busy,
                                  onTap: _openPasswordRecovery,
                                ),
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
                                  style: _noDecoration.copyWith(
                                    fontFamily: Brand.fontFamily,
                                    fontSize: 13,
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 28),
                              SizedBox(
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: busy ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Brand.accent,
                                    foregroundColor: Brand.voidBlack,
                                    disabledBackgroundColor: Brand.accent
                                        .withValues(alpha: 0.45),
                                    disabledForegroundColor: Brand.voidBlack
                                        .withValues(alpha: 0.55),
                                    elevation: 0,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        Brand.radius,
                                      ),
                                    ),
                                    textStyle: _noDecoration.copyWith(
                                      fontFamily: Brand.fontFamily,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: Text(
                                    busy
                                        ? l10n.loginSigningIn
                                        : l10n.loginSignIn,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: _LoginTextAction(
                                  label: l10n.loginContinueWithoutAccount,
                                  color: onSurface.withValues(alpha: 0.78),
                                  enabled: !busy,
                                  onTap: () => ref
                                      .read(authProvider.notifier)
                                      .continueAsGuest(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.loginGuestLimitsHint,
                                textAlign: TextAlign.center,
                                style: _noDecoration.copyWith(
                                  fontFamily: Brand.fontFamily,
                                  fontSize: 12,
                                  height: 1.4,
                                  color: onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain tappable label — never uses [TextButton] (app theme underlines / fills it).
class _LoginTextAction extends StatefulWidget {
  const _LoginTextAction({
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_LoginTextAction> createState() => _LoginTextActionState();
}

class _LoginTextActionState extends State<_LoginTextAction> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? (widget.color.withValues(alpha: _hovered ? 1 : widget.color.a))
        : widget.color.withValues(alpha: 0.4);

    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: Brand.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
              decoration: TextDecoration.none,
              decorationColor: Colors.transparent,
              decorationThickness: 0,
            ),
          ),
        ),
      ),
    );
  }
}
