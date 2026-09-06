import 'package:elp_gui/generated/multipass.pb.dart';
import 'package:elp_gui/llm/catalogue/top_picks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mergeTopPicks prefers curated big names and skips community fillers', () {
    final recommended = [
      ModelSuggestion(
        id: 'nightmedia/random-7b',
        name: 'Random Community 7B',
        provider: 'nightmedia',
        score: 99,
        fitLevel: 'perfect',
      ),
      ModelSuggestion(
        id: 'Qwen2.5-7B-Instruct-Q4_K_M',
        name: 'Qwen2.5 7B Instruct',
        provider: 'Qwen',
        score: 88,
        fitLevel: 'good',
        bestQuant: 'Q4_K_M',
      ),
    ];
    final fitted = [
      ModelSuggestion(
        id: 'google/gemma-2-9b-it',
        name: 'Gemma 2 9B IT',
        provider: 'Google',
        score: 92,
        fitLevel: 'perfect',
      ),
      ModelSuggestion(
        id: 'mconcat/obscure-model',
        name: 'Obscure',
        provider: 'mconcat',
        score: 95,
        fitLevel: 'perfect',
      ),
    ];

    final merged = mergeTopPicks(
      recommended: recommended,
      fitted: fitted,
      targetCount: 14,
    );

    expect(merged.length, kCuratedTopPicks.length);
    expect(merged.first.id.toLowerCase(), contains('gemma'));
    expect(
      merged.any((m) => m.id.contains('Qwen2.5-7B-Instruct')),
      isTrue,
    );
    expect(merged.any((m) => m.id.contains('nightmedia')), isFalse);
    expect(merged.any((m) => m.id.contains('mconcat')), isFalse);
  });

  test('modelMatchesCurated is case-insensitive and fuzzy', () {
    final model = ModelSuggestion(
      id: 'org/Qwen2.5-Coder-7B-Instruct-GGUF',
      name: 'Qwen2.5 Coder',
      hfRepo: 'bartowski/Qwen2.5-Coder-7B-Instruct-GGUF',
    );
    expect(
      modelMatchesCurated(
        model,
        kCuratedTopPicks.firstWhere((p) => p.query.contains('Coder')),
      ),
      isTrue,
    );
  });
}
