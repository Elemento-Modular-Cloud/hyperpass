import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../confirmation_dialog.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../page_surface.dart';
import '../widgets/launchpad_button.dart';
import 'cloud_init_store.dart';
import 'yaml_highlight_controller.dart';

class CloudInitScreen extends ConsumerStatefulWidget {
  static const sidebarKey = 'cloud-init';

  const CloudInitScreen({super.key});

  @override
  ConsumerState<CloudInitScreen> createState() => _CloudInitScreenState();
}

class _CloudInitScreenState extends ConsumerState<CloudInitScreen> {
  String? _selectedName;
  final _editorController = YamlHighlightController();
  String _savedContents = '';
  String? _parseError;
  var _loadingContent = false;

  bool get _dirty =>
      _selectedName != null && _editorController.text != _savedContents;

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  Future<void> _selectConfig(String name) async {
    if (_selectedName == name) return;
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (discard != true) return;
    }
    await _loadConfig(name);
  }

  Future<void> _loadConfig(String name) async {
    setState(() {
      _selectedName = name;
      _loadingContent = true;
      _parseError = null;
    });
    try {
      final store = await ref.read(cloudInitStoreProvider.future);
      final contents = await store.read(name);
      if (!mounted) return;
      setState(() {
        _editorController.text = contents;
        _savedContents = contents;
        _loadingContent = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingContent = false;
        _parseError = '$error';
      });
    }
  }

  Future<bool?> _confirmDiscard() {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ConfirmationDialog(
        title: l10n.cloudInitDiscardTitle,
        body: Text(l10n.cloudInitDiscardBody),
        actionText: l10n.cloudInitDiscardAction,
        onAction: () => Navigator.pop(dialogContext, true),
        inactionText: l10n.commonCancel,
        onInaction: () => Navigator.pop(dialogContext, false),
      ),
    );
  }

  Future<void> _createConfig() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _promptName(
      title: l10n.cloudInitNewTitle,
      actionText: l10n.cloudInitNew,
    );
    if (name == null) return;

    try {
      final store = await ref.read(cloudInitStoreProvider.future);
      final existing = await store.list();
      if (existing.any((c) => c.name == name)) {
        _showError(l10n.cloudInitErrorExists(name));
        return;
      }
      await store.write(name, defaultCloudInitTemplate);
      ref.invalidate(cloudInitConfigsProvider);
      await _loadConfig(name);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _importConfig() async {
    final l10n = AppLocalizations.of(context)!;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'YAML', extensions: ['yaml', 'yml']),
      ],
    );
    if (file == null) return;

    final name = await _promptName(
      title: l10n.cloudInitImportTitle,
      actionText: l10n.cloudInitImport,
      initialValue: _suggestedNameFromPath(file.name),
    );
    if (name == null) return;

    try {
      final store = await ref.read(cloudInitStoreProvider.future);
      final existing = await store.list();
      if (existing.any((c) => c.name == name)) {
        _showError(l10n.cloudInitErrorExists(name));
        return;
      }
      await store.importFile(file.path, name);
      ref.invalidate(cloudInitConfigsProvider);
      await _loadConfig(name);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _renameConfig() async {
    final current = _selectedName;
    if (current == null) return;
    final l10n = AppLocalizations.of(context)!;
    final name = await _promptName(
      title: l10n.cloudInitRenameTitle,
      actionText: l10n.cloudInitRenameAction,
      initialValue: current,
    );
    if (name == null || name == current) return;

    try {
      if (_dirty) {
        final saved = await _saveConfig(showErrors: true);
        if (!saved) return;
      }
      final store = await ref.read(cloudInitStoreProvider.future);
      await store.rename(current, name);
      ref.invalidate(cloudInitConfigsProvider);
      await _loadConfig(name);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _deleteConfig() async {
    final current = _selectedName;
    if (current == null) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ConfirmationDialog(
        title: l10n.cloudInitDeleteTitle,
        body: Text(l10n.cloudInitDeleteBody(current)),
        actionText: l10n.commonDelete,
        onAction: () => Navigator.pop(dialogContext, true),
        inactionText: l10n.commonCancel,
        onInaction: () => Navigator.pop(dialogContext, false),
      ),
    );
    if (confirmed != true) return;

    try {
      final store = await ref.read(cloudInitStoreProvider.future);
      await store.delete(current);
      ref.invalidate(cloudInitConfigsProvider);
      setState(() {
        _selectedName = null;
        _editorController.clear();
        _savedContents = '';
        _parseError = null;
      });
    } catch (error) {
      _showError('$error');
    }
  }

  Future<bool> _saveConfig({bool showErrors = true}) async {
    final current = _selectedName;
    if (current == null) return false;
    final l10n = AppLocalizations.of(context)!;
    final contents = _editorController.text;

    try {
      CloudInitStore.validateYaml(contents);
      setState(() => _parseError = null);
    } on FormatException catch (error) {
      setState(() => _parseError = error.message);
      if (showErrors) {
        _showError(l10n.cloudInitErrorInvalidYaml(error.message));
      }
      return false;
    }

    try {
      final store = await ref.read(cloudInitStoreProvider.future);
      await store.write(current, contents);
      ref.invalidate(cloudInitConfigsProvider);
      setState(() => _savedContents = contents);
      return true;
    } catch (error) {
      if (showErrors) _showError('$error');
      return false;
    }
  }

  Future<String?> _promptName({
    required String title,
    required String actionText,
    String? initialValue,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialValue ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: CompactLayout.dialogWidth(dialogContext, 420),
            child: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.cloudInitNameLabel,
                  helperText: l10n.cloudInitNameHelper,
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return l10n.cloudInitNameErrorEmpty;
                  if (!CloudInitStore.isValidName(name)) {
                    return l10n.cloudInitNameErrorInvalid;
                  }
                  return null;
                },
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.commonCancel),
            ),
            LaunchPadButton.primary(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: Text(actionText),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _suggestedNameFromPath(String fileName) {
    final base = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    return sanitized.isEmpty ? 'user-data' : sanitized;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final configsAsync = ref.watch(cloudInitConfigsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: PageSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.cloudInitLabel,
              style: const TextStyle(fontSize: 37, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cloudInitSubtitle,
              style: TextStyle(
                fontSize: 14,
                color: onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: configsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('$error')),
                data: (configs) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Toolbar(
                      onNew: _createConfig,
                      onImport: _importConfig,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 280,
                            child: _ConfigList(
                              configs: configs,
                              selectedName: _selectedName,
                              onSelect: _selectConfig,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: _buildEditor(l10n, onSurface)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(AppLocalizations l10n, Color onSurface) {
    if (_selectedName == null) {
      return Center(
        child: Text(
          l10n.cloudInitSelectPrompt,
          style: TextStyle(
            fontSize: 16,
            color: onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (_loadingContent) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedName!,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              ),
            ),
            if (_dirty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  l10n.cloudInitUnsaved,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
              ),
            IconButton(
              tooltip: l10n.cloudInitRenameAction,
              onPressed: _renameConfig,
              icon: const Icon(Icons.drive_file_rename_outline),
            ),
            IconButton(
              tooltip: l10n.commonDelete,
              onPressed: _deleteConfig,
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: _dirty
                  ? () {
                      _editorController.text = _savedContents;
                      setState(() => _parseError = null);
                    }
                  : null,
              child: Text(l10n.cloudInitDiscardAction),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _dirty ? () => _saveConfig() : null,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
        if (_parseError != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.cloudInitErrorInvalidYaml(_parseError!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _editorController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontFamily: 'UbuntuMono',
              fontSize: 13,
              height: 1.4,
              color: onSurface,
            ),
            decoration: InputDecoration(
              filled: true,
              hintText: l10n.cloudInitEditorHint,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onNew,
    required this.onImport,
  });

  final VoidCallback onNew;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        TextButton.icon(
          onPressed: onNew,
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.cloudInitNew),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.file_upload_outlined, size: 18),
          label: Text(l10n.cloudInitImport),
        ),
      ],
    );
  }
}

class _ConfigList extends StatelessWidget {
  const _ConfigList({
    required this.configs,
    required this.selectedName,
    required this.onSelect,
  });

  final List<CloudInitConfigInfo> configs;
  final String? selectedName;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: onSurface.withValues(alpha: 0.2)),
      ),
      child: configs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.cloudInitEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          : ListView.separated(
              itemCount: configs.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: onSurface.withValues(alpha: 0.12),
              ),
              itemBuilder: (context, index) {
                final config = configs[index];
                final selected = config.name == selectedName;
                return ListTile(
                  selected: selected,
                  title: Text(config.name),
                  onTap: () => onSelect(config.name),
                );
              },
            ),
    );
  }
}
