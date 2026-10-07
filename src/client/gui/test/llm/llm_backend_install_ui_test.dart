import 'package:elp_gui/llm/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appendLogLines splits and skips empties', () {
    final lines = LlmBackendInstallUi.appendLogLines(
      const ['keep'],
      'a\n\nb\n',
    );
    expect(lines, ['keep', 'a', 'b']);
  });

  test('appendLogLines caps at maxLogLines', () {
    final seed = List<String>.generate(190, (i) => 'line-$i');
    final lines = LlmBackendInstallUi.appendLogLines(
      seed,
      List<String>.generate(20, (i) => 'new-$i').join('\n'),
    );
    expect(lines.length, LlmBackendInstallUi.maxLogLines);
    expect(lines.first, 'line-10');
    expect(lines.last, 'new-19');
  });
}
