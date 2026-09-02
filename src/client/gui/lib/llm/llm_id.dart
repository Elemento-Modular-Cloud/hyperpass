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

const openaiBaseUrl = 'https://127.0.0.1:7777/v1';
const llmHfTokenSettingKey = 'local.llm.hf-token';
