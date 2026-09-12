import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const llmLoadPrefsKey = 'llm_load_params_v1';

Map<String, dynamic>? readLlmLoadPrefs(
  SharedPreferences prefs,
  String modelId,
) {
  if (modelId.isEmpty) return null;
  final raw = prefs.getString(llmLoadPrefsKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final entry = decoded[modelId];
    if (entry is Map<String, dynamic>) return entry;
    if (entry is Map) return Map<String, dynamic>.from(entry);
  } catch (_) {}
  return null;
}

Future<void> writeLlmLoadPrefs(
  SharedPreferences prefs,
  String modelId,
  Map<String, dynamic> form,
) async {
  if (modelId.isEmpty) return;
  Map<String, dynamic> all = {};
  final raw = prefs.getString(llmLoadPrefsKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) all = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  all[modelId] = form;
  await prefs.setString(llmLoadPrefsKey, jsonEncode(all));
}
