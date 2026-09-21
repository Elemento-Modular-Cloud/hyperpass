import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalogue/catalogue.dart';
import '../logger.dart';
import '../providers.dart';
import 'auth_provider.dart';
import 'spacedock_config.dart';

/// Pushes the Portal JWT into elpd's in-memory `local.spacedock.token` and
/// refreshes the image catalogue. Watched from [App] so it stays alive.
/// An empty token (guest / logout) still forces a find so gated images drop.
final spacedockCatalogSyncProvider = Provider<void>((ref) {
  final token = ref.watch(spacedockAccessTokenProvider);
  final daemonUp = ref.watch(daemonAvailableProvider);
  if (!daemonUp) return;

  Future.microtask(() async {
    try {
      await ref
          .read(grpcClientProvider)
          .set(SpacedockConfig.tokenSettingKey, token ?? '');
      await ref.read(grpcClientProvider).find(forceUpdate: true);
      ref.invalidate(imagesProvider);
    } catch (e, st) {
      logger.w('Could not sync Spacedock catalog token',
          error: e, stackTrace: st);
    }
  });
});
