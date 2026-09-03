import 'package:flutter/material.dart';

import '../brand.dart';
import '../l10n/app_localizations.dart';
import 'service_library.dart';

/// Owns a text controller per optional service parameter and collects the
/// values the user actually filled in.
class ServiceParameterEditors {
  ServiceParameterEditors(this.variables)
      : _controllers = {
          for (final variable in variables)
            variable.name: TextEditingController(),
        };

  final List<ServiceVariable> variables;
  final Map<String, TextEditingController> _controllers;

  bool get isEmpty => variables.isEmpty;

  TextEditingController controllerFor(String name) => _controllers[name]!;

  /// Only non-empty fields are returned. Omitted parameters stay as
  /// `{{placeholders}}`, which the service's own setup scripts fill in on
  /// first boot.
  Map<String, String> get values {
    final entered = <String, String>{};
    for (final MapEntry(key: name, value: controller) in _controllers.entries) {
      final value = controller.text.trim();
      if (value.isNotEmpty) entered[name] = value;
    }
    return entered;
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
  }
}

/// Editable list of every parameter a service declares, labelled with the
/// setting each one fills.
class ServiceParametersForm extends StatelessWidget {
  const ServiceParametersForm({required this.editors, super.key});

  final ServiceParameterEditors editors;

  @override
  Widget build(BuildContext context) {
    if (editors.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.serviceParametersTitle,
          style: const TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${l10n.serviceParametersCount(editors.variables.length)}'
          ' · ${l10n.serviceParametersOptional}',
          style: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 12,
            height: 1.35,
            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        for (final variable in editors.variables)
          _ParameterField(
            variable: variable,
            controller: editors.controllerFor(variable.name),
            hint: l10n.serviceParameterGeneratedHint,
          ),
      ],
    );
  }
}

class _ParameterField extends StatelessWidget {
  const _ParameterField({
    required this.variable,
    required this.controller,
    required this.hint,
  });

  final ServiceVariable variable;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // Fall back to the placeholder name so a labelled field still shows which
    // `{{...}}` it fills.
    final helper =
        variable.documentation ?? (variable.key != null ? variable.name : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        style: TextStyle(
          fontFamily: 'UbuntuMono',
          fontSize: 13,
          color: onSurface,
        ),
        decoration: InputDecoration(
          labelText: variable.label,
          labelStyle: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 14,
            color: onSurface.withValues(alpha: 0.9),
          ),
          hintText: hint,
          hintStyle: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: onSurface.withValues(alpha: 0.4),
          ),
          helperText: helper,
          helperMaxLines: 3,
          helperStyle: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.6),
          ),
          isDense: true,
        ),
      ),
    );
  }
}
