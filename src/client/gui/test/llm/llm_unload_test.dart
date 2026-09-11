import 'package:elp_gui/llm/providers.dart';
import 'package:elp_gui/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending unloads can record several instance ids at once', () {
    final container = ProviderContainer(
      overrides: [
        loadedModelsProvider.overrideWith((ref) => const Stream.empty()),
        daemonAvailableProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(pendingLlmUnloadsProvider.notifier).addAll(['a', 'b', '']);
    expect(container.read(pendingLlmUnloadsProvider), {'a', 'b'});
  });
}
