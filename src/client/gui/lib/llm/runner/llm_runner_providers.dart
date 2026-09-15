import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/feature_access.dart';
import '../../providers.dart';
import '../providers.dart';
import 'llm_accelerator.dart';

const llmRunnerSelectionPrefsKey = 'llm_runner_accelerators_v1';

final llmRunnerSnapshotProvider = Provider<LlmRunnerSnapshot>((ref) {
  final info = ref.watch(daemonInfoProvider).asData?.value;
  final backends = ref.watch(llmBackendsProvider).asData?.value;
  return probeLlmRunner(
    info: info,
    backends: backends,
    platform: defaultTargetPlatform,
  );
});

class LlmRunnerStoredSelection extends Notifier<BuiltSet<String>?> {
  @override
  BuiltSet<String>? build() {
    final raw = ref
        .watch(sharedPreferencesProvider)
        .getString(llmRunnerSelectionPrefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return BuiltSet<String>(decoded.whereType<String>());
      }
    } catch (_) {}
    return null;
  }

  Future<void> setIds(Iterable<String> ids) async {
    final next = BuiltSet<String>(ids);
    state = next;
    await ref.read(sharedPreferencesProvider).setString(
          llmRunnerSelectionPrefsKey,
          jsonEncode(next.toList()),
        );
  }
}

final llmRunnerStoredSelectionProvider =
    NotifierProvider<LlmRunnerStoredSelection, BuiltSet<String>?>(
  LlmRunnerStoredSelection.new,
);

/// Effective accelerator ids feeding the runner (never empty when a CPU exists).
final llmRunnerSelectedIdsProvider = Provider<BuiltSet<String>>((ref) {
  final snapshot = ref.watch(llmRunnerSnapshotProvider);
  final stored = ref.watch(llmRunnerStoredSelectionProvider);
  final canCombine = ref.watch(featureAccessProvider).canCombineAccelerators;
  final usable = {
    for (final accelerator in snapshot.accelerators)
      if (accelerator.selectable) accelerator.id,
  };

  if (stored != null) {
    final kept = [
      for (final id in stored)
        if (usable.contains(id)) id,
    ];
    if (kept.isNotEmpty) {
      if (!canCombine && kept.length > 1) return BuiltSet({kept.first});
      return BuiltSet(kept);
    }
  }
  return BuiltSet(defaultSelectedAcceleratorIds(snapshot.accelerators));
});
