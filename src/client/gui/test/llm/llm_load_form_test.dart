import 'package:elp_gui/llm/llm_load_form.dart';
import 'package:elp_gui/llm/llm_load_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults match leading-tool load settings', () {
    final form = LlmLoadForm();
    expect(form.ctxSize, 8192);
    expect(form.maxTokens, 0);
    expect(form.nGpuLayers, 'auto');
    expect(form.cacheType, 'q8_0');
    expect(form.flashAttn, 'auto');
    expect(form.cacheReuse, 256);
    expect(form.fit, isTrue);
    expect(form.moeOffload, 'auto');
  });

  test('suggested context wins when there is no last-used map', () {
    final form = LlmLoadForm.fromJson(null, suggestedCtx: 32768);
    expect(form.ctxSize, 32768);
  });

  test('last-used json overrides suggested context', () {
    final form = LlmLoadForm.fromJson(
      {'ctx_size': 4096, 'gpu_offload': 'cpu'},
      suggestedCtx: 32768,
    );
    expect(form.ctxSize, 4096);
    expect(form.gpuOffload, 'cpu');
    expect(form.nGpuLayers, '0');
  });

  test('proto mapping sets llama knobs and both kv types', () {
    final form = LlmLoadForm(
      ctxSize: 16384,
      gpuOffload: 'custom',
      customGpuLayers: 24,
      cacheType: 'q4_0',
      keepInRam: true,
    );
    final params = form.toProto();
    expect(params.ctxSize, 16384);
    expect(params.nGpuLayers, '24');
    expect(params.cacheTypeK, 'q4_0');
    expect(params.cacheTypeV, 'q4_0');
    expect(params.loadMode, 'mmap+mlock');
  });

  test('mlx omits llama-only proto fields', () {
    final params = LlmLoadForm(runtime: 'mlx', ctxSize: 4096).toProto();
    expect(params.ctxSize, 4096);
    expect(params.nGpuLayers, isEmpty);
    expect(params.cacheTypeK, isEmpty);
  });

  test('rejects invalid numbers', () {
    expect(LlmLoadForm(ctxSize: 0).isValid, isFalse);
    expect(LlmLoadForm(maxTokens: -1).isValid, isFalse);
    expect(LlmLoadForm().isValid, isTrue);
  });

  test('prefs remember last-used settings per model', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await writeLlmLoadPrefs(
      prefs,
      'Llama-3.1-8B',
      LlmLoadForm(ctxSize: 12288, gpuOffload: 'all').toJson(),
    );
    expect(readLlmLoadPrefs(prefs, 'Gemma-2-2B'), isNull);
    final stored = readLlmLoadPrefs(prefs, 'Llama-3.1-8B');
    expect(stored, isNotNull);
    expect(LlmLoadForm.fromJson(stored).ctxSize, 12288);
    expect(LlmLoadForm.fromJson(stored).gpuOffload, 'all');
  });
}
