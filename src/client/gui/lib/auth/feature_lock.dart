import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import 'auth_provider.dart';

/// Shows why a feature is locked and offers Sign in.
void promptFeatureLocked(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final onSurface = Theme.of(context).colorScheme.onSurface;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 0,
      backgroundColor:
          (isDark ? Brand.voidBlack : Brand.white).withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        side: BorderSide(
          color: onSurface.withValues(alpha: isDark ? 0.18 : 0.12),
        ),
      ),
      // Custom action avoids the app-wide filled TextButton theme.
      content: Row(
        children: [
          Expanded(
            child: Text(
              l10n.featureLockedSignIn,
              style: TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 14,
                color: onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentSnackBar();
              ref.read(authProvider.notifier).requestSignIn();
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Brand.primary,
              disabledForegroundColor: Brand.primary.withValues(alpha: 0.45),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Brand.radius),
              ),
              textStyle: const TextStyle(
                fontFamily: Brand.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(l10n.loginSignIn),
          ),
        ],
      ),
    ),
  );
}
