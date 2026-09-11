import 'package:built_collection/built_collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sidebar.dart';
import '../../vm_table/search_box.dart';
import '../providers.dart';

class SelectedLlmInstancesNotifier extends Notifier<BuiltSet<String>> {
  @override
  BuiltSet<String> build() {
    // Listen rather than watch: watching rebuilds this notifier and wipes
    // selection back to BuiltSet() in the middle of a bulk Unload.
    ref.listen(llmSearchProvider, (_, __) {
      if (state.isNotEmpty) state = BuiltSet();
    });
    ref.listen(sidebarKeyProvider, (_, __) {
      if (state.isNotEmpty) state = BuiltSet();
    });
    ref.listen(loadedLlmIdsProvider, (_, ids) {
      final available = {for (final id in ids) id.instanceId};
      final next = state.rebuild(
        (set) => set.removeWhere((id) => !available.contains(id)),
      );
      if (next != state) state = next;
    });
    return BuiltSet();
  }

  void set(BuiltSet<String> newState) => state = newState;

  void toggle(String id, bool isSelected) {
    state = state.rebuild((set) {
      isSelected ? set.add(id) : set.remove(id);
    });
  }
}

final selectedLlmInstancesProvider =
    NotifierProvider<SelectedLlmInstancesNotifier, BuiltSet<String>>(
  SelectedLlmInstancesNotifier.new,
);
