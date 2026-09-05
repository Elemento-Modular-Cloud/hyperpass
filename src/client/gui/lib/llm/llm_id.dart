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

/// OpenAI-compatible gateway as seen from the host.
const openaiBaseUrl = 'https://127.0.0.1:7777/v1';

/// Same gateway as seen from an Electros LaunchPad VM on the 192.168.67.0/24 network.
/// The API binds 127.0.0.1 and 192.168.67.1; VMs use this URL.
const openaiVmBaseUrl = 'https://192.168.67.1:7777/v1';

const llmHfTokenSettingKey = 'local.llm.hf-token';
