import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../brand.dart';
import '../../providers.dart';

/// Provider mark + accent for model catalogue cards.
class ModelProviderBranding {
  const ModelProviderBranding({
    required this.displayName,
    required this.logoAsset,
    required this.accent,
    this.logoTint,
  });

  final String displayName;
  final String logoAsset;
  final Color accent;
  final Color? logoTint;
}

const _fallback = ModelProviderBranding(
  displayName: 'Model',
  logoAsset: 'assets/atomos.svg',
  accent: Brand.accent,
);

const _byFamily = <String, ModelProviderBranding>{
  'google': ModelProviderBranding(
    displayName: 'Google',
    logoAsset: 'assets/llm/google.svg',
    accent: Color(0xFF4285F4),
  ),
  'gemma': ModelProviderBranding(
    displayName: 'Google',
    logoAsset: 'assets/llm/google.svg',
    accent: Color(0xFF4285F4),
  ),
  'meta': ModelProviderBranding(
    displayName: 'Meta',
    logoAsset: 'assets/llm/meta.svg',
    accent: Color(0xFF0668E1),
  ),
  'llama': ModelProviderBranding(
    displayName: 'Meta',
    logoAsset: 'assets/llm/meta.svg',
    accent: Color(0xFF0668E1),
  ),
  'microsoft': ModelProviderBranding(
    displayName: 'Microsoft',
    logoAsset: 'assets/llm/microsoft.svg',
    accent: Color(0xFF00A4EF),
  ),
  'phi': ModelProviderBranding(
    displayName: 'Microsoft',
    logoAsset: 'assets/llm/microsoft.svg',
    accent: Color(0xFF00A4EF),
  ),
  'nvidia': ModelProviderBranding(
    displayName: 'NVIDIA',
    logoAsset: 'assets/llm/nvidia.svg',
    accent: Color(0xFF76B900),
  ),
  'nemotron': ModelProviderBranding(
    displayName: 'NVIDIA',
    logoAsset: 'assets/llm/nvidia.svg',
    accent: Color(0xFF76B900),
  ),
  'deepseek': ModelProviderBranding(
    displayName: 'DeepSeek',
    logoAsset: 'assets/llm/deepseek.svg',
    accent: Color(0xFF4D6BFE),
  ),
  'mistral': ModelProviderBranding(
    displayName: 'Mistral',
    logoAsset: 'assets/llm/mistral.svg',
    accent: Color(0xFFFF7000),
  ),
  'mixtral': ModelProviderBranding(
    displayName: 'Mistral',
    logoAsset: 'assets/llm/mistral.svg',
    accent: Color(0xFFFF7000),
  ),
  'qwen': ModelProviderBranding(
    displayName: 'Qwen',
    logoAsset: 'assets/llm/qwen.png',
    accent: Color(0xFF6366F1),
  ),
  'alibaba': ModelProviderBranding(
    displayName: 'Qwen',
    logoAsset: 'assets/llm/qwen.png',
    accent: Color(0xFF6366F1),
  ),
  'ibm': ModelProviderBranding(
    displayName: 'IBM',
    logoAsset: 'assets/llm/ibm.svg',
    accent: Color(0xFF054ADA),
  ),
  'granite': ModelProviderBranding(
    displayName: 'IBM',
    logoAsset: 'assets/llm/ibm.svg',
    accent: Color(0xFF054ADA),
  ),
  'huggingface': ModelProviderBranding(
    displayName: 'Hugging Face',
    logoAsset: 'assets/llm/huggingface.svg',
    accent: Color(0xFFFFD21E),
  ),
  'hf': ModelProviderBranding(
    displayName: 'Hugging Face',
    logoAsset: 'assets/llm/huggingface.svg',
    accent: Color(0xFFFFD21E),
  ),
};

final _knownProviderKeys = _byFamily.keys.toSet();

bool isKnownModelProvider(String providerOrId) {
  final key = providerOrId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  if (key.isEmpty) return false;
  return _knownProviderKeys.any((k) => key.contains(k));
}

ModelProviderBranding modelProviderBranding({
  required String provider,
  String id = '',
  String name = '',
  String hfRepo = '',
}) {
  // Collapse punctuation/spaces so "Hugging Face" still matches "huggingface".
  final haystack =
      '$provider $id $name $hfRepo'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  for (final entry in _byFamily.entries) {
    if (haystack.contains(entry.key)) return entry.value;
  }
  return _fallback;
}

ModelProviderBranding brandingForSuggestion(ModelSuggestion model) =>
    modelProviderBranding(
      provider: model.provider,
      id: model.id,
      name: model.name,
      hfRepo: model.hfRepo,
    );

ModelProviderBranding brandingForLoaded(LoadedModelInfo model) =>
    modelProviderBranding(
      provider: '',
      id: model.modelId,
      name: model.openaiId.isNotEmpty ? model.openaiId : model.modelId,
      hfRepo: model.path,
    );

class ModelProviderBadge extends StatelessWidget {
  const ModelProviderBadge({
    required this.branding,
    this.size = 40,
    this.semanticsLabel,
    super.key,
  });

  final ModelProviderBranding branding;
  final double size;
  final String? semanticsLabel;

  Widget _letterFallback() {
    return Center(
      child: Text(
        branding.displayName.isNotEmpty
            ? branding.displayName[0].toUpperCase()
            : '?',
        style: TextStyle(
          color: branding.accent,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }

  Widget _logo() {
    final asset = branding.logoAsset;
    if (asset.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        fit: BoxFit.contain,
        colorFilter: branding.logoTint == null
            ? null
            : ColorFilter.mode(branding.logoTint!, BlendMode.srcIn),
        placeholderBuilder: (_) => _letterFallback(),
        errorBuilder: (_, __, ___) => _letterFallback(),
      );
    }
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _letterFallback(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? branding.displayName,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: branding.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Brand.radius),
          border: Border.all(color: branding.accent.withValues(alpha: 0.4)),
        ),
        padding: EdgeInsets.all(size * 0.16),
        child: _logo(),
      ),
    );
  }
}
