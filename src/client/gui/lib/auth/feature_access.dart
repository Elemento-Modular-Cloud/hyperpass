import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'auth_state.dart';

/// Product capabilities derived from auth (and later, license).
///
/// Today: signed-in Portal accounts get full access; guests are limited to
/// Ubuntu VMs (no LLMs / services). Later: full access will require a
/// purchased license on a signed-in account.
class FeatureAccess {
  const FeatureAccess({
    required this.signedIn,
    required this.guest,
    this.canCombineAccelerators = false,
  });

  final bool signedIn;
  final bool guest;

  /// Full product surface. Later: `signedIn && hasPurchasedLicense`.
  bool get hasFullProductAccess => signedIn;

  bool get canUseLlms => hasFullProductAccess;
  bool get canUseServices => hasFullProductAccess;
  bool get ubuntuImagesOnly => !hasFullProductAccess;

  /// Treat several accelerators (CPU + GPU + MPU) as one LLM runner.
  ///
  /// Off for every account today so the Runner page can present the paywall
  /// surface. Later: a purchased license tier on a signed-in account.
  final bool canCombineAccelerators;
}

final featureAccessProvider = Provider<FeatureAccess>((ref) {
  final auth = ref.watch(authProvider);
  return switch (auth) {
    AuthAuthenticated() => const FeatureAccess(signedIn: true, guest: false),
    AuthGuest() => const FeatureAccess(signedIn: false, guest: true),
    _ => const FeatureAccess(signedIn: false, guest: false),
  };
});
