import 'package:elp_gui/providers.dart';
import 'package:elp_gui/services/compose/compose_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({
      composeCurrentIntentPrefsKey: 'lab',
    });
    final prefs = await SharedPreferences.getInstance();
    final result = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(result.dispose);
    return result;
  }

  test('shift-style select keeps more than one node', () async {
    final c = await container();
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    notifier.addLlm(modelId: 'qwen');
    final ids = c.read(composeEditorProvider).graph.nodes.map((n) => n.id);
    expect(ids.length, 2);

    notifier.selectNode(ids.first);
    notifier.selectNode(ids.last, additive: true);
    expect(c.read(composeEditorProvider).selectedNodeIds, ids.toSet());
  });

  test('moveNodes shifts every selected member', () async {
    final c = await container();
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    notifier.addLlm(modelId: 'qwen');
    final nodes = c.read(composeEditorProvider).graph.nodes;
    notifier.selectNodes({nodes[0].id, nodes[1].id});
    notifier.moveNodes({
      nodes[0].id: (nodes[0].x + 40, nodes[0].y + 10),
      nodes[1].id: (nodes[1].x + 40, nodes[1].y + 10),
    });
    final moved = c.read(composeEditorProvider).graph.nodes;
    expect(moved[0].x, nodes[0].x + 40);
    expect(moved[1].y, nodes[1].y + 10);
  });

  test('removeSelected deletes the whole set', () async {
    final c = await container();
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    notifier.addLlm(modelId: 'qwen');
    notifier.selectAll();
    notifier.removeSelected();
    expect(c.read(composeEditorProvider).graph.nodes, isEmpty);
    expect(c.read(composeEditorProvider).selectedNodeIds, isEmpty);
  });
}
