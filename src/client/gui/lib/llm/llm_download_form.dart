import 'llm_features.dart';

enum LlmDownloadQuantMode { recommended, allGguf }

class LlmDownloadForm {
  LlmDownloadForm({
    Set<String>? runtimes,
    this.quantMode = LlmDownloadQuantMode.recommended,
  }) : runtimes = {...?runtimes};

  final Set<String> runtimes;
  LlmDownloadQuantMode quantMode;

  bool get includesLlama => runtimes.any(isLlamaRuntime);

  bool get isValid => runtimes.isNotEmpty;

  LlmDownloadForm copy() => LlmDownloadForm(
        runtimes: runtimes,
        quantMode: quantMode,
      );
}
