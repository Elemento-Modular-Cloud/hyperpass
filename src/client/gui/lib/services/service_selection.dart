import 'package:built_collection/built_collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../sidebar.dart';
import '../vm_table/search_box.dart';

class SelectedServiceInstancesNotifier extends Notifier<BuiltSet<VmId>> {
  @override
  BuiltSet<VmId> build() {
    ref.watch(serviceSearchProvider);
    ref.watch(sidebarKeyProvider);
    ref.listen(serviceInstanceIdsProvider, (_, availableIds) {
      state = availableIds.intersection(state);
    });
    return BuiltSet();
  }

  void set(BuiltSet<VmId> newState) => state = newState;

  void toggle(VmId id, bool isSelected) {
    state = state.rebuild((set) {
      isSelected ? set.add(id) : set.remove(id);
    });
  }
}

final selectedServiceInstancesProvider =
    NotifierProvider<SelectedServiceInstancesNotifier, BuiltSet<VmId>>(
  SelectedServiceInstancesNotifier.new,
);
