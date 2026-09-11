import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'brand.dart';
import 'l10n/app_localizations.dart';
import 'widgets/launchpad_button.dart';
import 'providers.dart';

/// Banner shown when Multipass is reachable but the GUI client cert is not trusted.
class MultipassAuthBanner extends ConsumerWidget {
  const MultipassAuthBanner({super.key});

  static Future<void> showAuthDialog(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Brand.barrier,
      builder: (_) => const MultipassAuthDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsAuth = ref.watch(multipassNeedsAuthProvider);
    final showMultipass =
        ref.watch(guiSettingProvider(showMultipassInstancesKey)) != 'false';
    if (!needsAuth || !showMultipass) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Multipass requires authentication to show its instances.',
              ),
            ),
            TextButton(
              onPressed: () => showAuthDialog(context),
              child: const Text('Authenticate…'),
            ),
          ],
        ),
      ),
    );
  }
}

class MultipassAuthDialog extends ConsumerStatefulWidget {
  const MultipassAuthDialog({super.key});

  @override
  ConsumerState<MultipassAuthDialog> createState() =>
      _MultipassAuthDialogState();
}

class _MultipassAuthDialogState extends ConsumerState<MultipassAuthDialog> {
  final _controller = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    final client = ref.read(multipassGrpcClientProvider);
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await client.authenticate(_controller.text);
      ref.read(multipassNeedsAuthProvider.notifier).set(false);
      ref.invalidate(multipassVmInfosStreamProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: const Text('Authenticate with Multipass'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Passphrase'),
            onSubmitted: (_) => _authenticate(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        LaunchPadButton.secondary(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        LaunchPadButton.primary(
          onPressed: _busy ? null : _authenticate,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Authenticate'),
        ),
      ],
    );
  }
}
