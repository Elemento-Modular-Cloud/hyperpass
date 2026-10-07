import 'dart:io' show Platform;

class LlmInstanceId {
  final String instanceId;
  final String modelId;

  const LlmInstanceId({required this.instanceId, required this.modelId});

  String get sidebarKey => 'llm-${Uri.encodeComponent(instanceId)}';

  String get displayLabel => modelId;
}

const _reservedLlmSidebarKeys = {
  'llm-catalogue',
  'llm-instances',
  'llm-downloaded',
  'llm-credentials',
};

LlmInstanceId? parseSidebarLlmKey(String key) {
  if (_reservedLlmSidebarKeys.contains(key)) return null;
  if (!key.startsWith('llm-')) return null;
  final encoded = key.substring(4);
  if (encoded.isEmpty) return null;
  return LlmInstanceId(
    instanceId: Uri.decodeComponent(encoded),
    modelId: '',
  );
}

/// OpenAI-compatible gateway as seen from the host (`elp-llm-proxy`).
const openaiBaseUrl = 'http://127.0.0.1:11434/v1';

/// Same gateway as seen from an Electros LaunchPad VM.
/// macOS vmnet: 192.168.67.1; Linux/Windows QEMU NAT: 10.98.0.1.
String get openaiVmBaseUrl => Platform.isMacOS
    ? 'http://192.168.67.1:11434/v1'
    : 'http://10.98.0.1:11434/v1';

const llmHfTokenSettingKey = 'local.llm.hf-token';
