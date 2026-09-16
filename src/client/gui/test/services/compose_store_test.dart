import 'package:elp_gui/providers.dart';
import 'package:elp_gui/services/compose/compose_graph.dart';
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

  test('palette drops land on the visible canvas origin', () async {
    final c = await container();
    c.read(composeDropOriginProvider.notifier).set((420, 240));
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    final node = c.read(composeEditorProvider).graph.nodes.single;
    expect(node.x, 420);
    expect(node.y, 240);
  });

  test('moveNodes can skip persisting mid-gesture', () async {
    final c = await container();
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    final node = c.read(composeEditorProvider).graph.nodes.single;
    notifier.moveNodes({node.id: (node.x + 10, node.y + 10)}, persist: false);
    final prefs = c.read(sharedPreferencesProvider);
    final stored = loadComposeGraphs(prefs)['lab']!;
    expect(stored.nodes.single.x, node.x);
    expect(c.read(composeEditorProvider).graph.nodes.single.x, node.x + 10);
  });

  test('deleteSavedIntent drops a local graph and the open canvas', () async {
    final c = await container();
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    expect(notifier.savedIntentNames(), ['lab']);

    notifier.deleteSavedIntent('lab');
    expect(notifier.savedIntentNames(), isEmpty);
    expect(c.read(composeEditorProvider).graph.intentName, isEmpty);
    expect(loadComposeGraphs(c.read(sharedPreferencesProvider)), isEmpty);
  });

  test('deleteSavedIntent leaves a different open composition alone', () async {
    final c = await container();
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    expect(c.read(composeEditorProvider).viewEpoch, 0);
    notifier.openIntent('other');
    expect(c.read(composeEditorProvider).viewEpoch, 1);
    notifier.deleteSavedIntent('lab');

    expect(notifier.savedIntentNames(), isEmpty);
    expect(c.read(composeEditorProvider).graph.intentName, 'other');
  });

  test('compose picker hides leftover local graphs once the daemon list loads',
      () {
    expect(
      composePickerNames(
        saved: const ['gone', 'lab'],
        daemon: const ['lab'],
        current: 'gone',
        daemonListReady: true,
      ),
      ['lab'],
    );
    expect(
      composePickerNames(
        saved: const ['offline-draft'],
        daemon: const [],
        current: 'offline-draft',
        daemonListReady: false,
      ),
      ['offline-draft'],
    );
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

  test('setResources updates cpu ram disk and context', () async {
    final c = await container();
    final notifier = c.read(composeEditorProvider.notifier);
    notifier.addVm(image: '24.04', label: 'Ubuntu');
    notifier.addLlm(modelId: 'qwen', ctxSize: 8192);
    final nodes = c.read(composeEditorProvider).graph.nodes;
    final vm = nodes.firstWhere((n) => n.kind == ComposeNodeKind.vm);
    final llm = nodes.firstWhere((n) => n.kind == ComposeNodeKind.llm);

    notifier.setResources(
      vm.id,
      numCores: 8,
      memBytes: 4 * composeGibibyte,
      diskBytes: 40 * composeGibibyte,
    );
    notifier.setResources(llm.id, ctxSize: 32768);
    notifier.setResources(
      llm.id,
      maxTokens: 512,
      quant: 'Q4_K_M',
      runtime: 'llamacpp',
    );
    notifier.setResources(vm.id, cloudInitName: 'lab-init');

    final updated = c.read(composeEditorProvider).graph.nodes;
    final updatedVm = updated.firstWhere((n) => n.id == vm.id);
    final updatedLlm = updated.firstWhere((n) => n.id == llm.id);
    expect(updatedVm.numCores, 8);
    expect(updatedVm.memBytes, 4 * composeGibibyte);
    expect(updatedVm.diskBytes, 40 * composeGibibyte);
    expect(updatedVm.cloudInitName, 'lab-init');
    expect(updatedLlm.ctxSize, 32768);
    expect(updatedLlm.maxTokens, 512);
    expect(updatedLlm.quant, 'Q4_K_M');
    expect(updatedLlm.runtime, 'llamacpp');
  });
}
