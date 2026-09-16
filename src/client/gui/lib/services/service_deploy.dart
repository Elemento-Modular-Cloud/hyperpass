import 'dart:math';

import 'package:basics/basics.dart';
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../catalogue/launch_form.dart';
import '../cloud_init/cloud_init_store.dart';
import '../dropdown.dart';
import '../ffi.dart';
import '../intents/intents_screen.dart';
import '../l10n/app_localizations.dart';
import '../layout/compact_layout.dart';
import '../notifications.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../widgets/launchpad_button.dart';
import '../vm_details/cpus_slider.dart';
import '../vm_details/disk_slider.dart';
import '../vm_details/ram_slider.dart';
import '../vm_details/spec_input.dart';
import 'compose/compose_graph.dart';
import 'gateway_ca.dart';
import 'service_branding.dart';
import 'service_cloud_init.dart';
import 'service_instance_id.dart';
import 'service_intent_member.dart';
import 'service_library.dart';
import 'service_parameters_form.dart';

export 'service_intent_member.dart';

/// The services target Ubuntu (docker.io, docker-compose-v2), which is also
/// what the daemon launches when no image is requested.
const _serviceOs = 'Ubuntu';

/// Sentinel dropdown value for "create a new intent" (mirrors the private
/// constant of the same name in launch_form.dart — a leading NUL can never
/// be typed into a text field, so this can't collide with a real intent
/// name).
const _createNewIntentValue = '\u0000__create_new_intent__';

Future<void> showServiceDeployDialog(
  BuildContext context,
  MarketplaceService service,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ServiceDeployDialog(service: service),
  );
}

class _ServiceDeployDialog extends ConsumerStatefulWidget {
  const _ServiceDeployDialog({required this.service});

  final MarketplaceService service;

  @override
  ConsumerState<_ServiceDeployDialog> createState() =>
      _ServiceDeployDialogState();
}

class _ServiceDeployDialogState extends ConsumerState<_ServiceDeployDialog> {
  final _formKey = GlobalKey<FormState>();
  final _request = LaunchRequest();
  late final ServiceParameterEditors _parameters;
  late final String _generatedName;
  String? _error;
  String? _selectedIntent;
  String _newIntentName = '';
  String _intentRole = '';

  @override
  void initState() {
    super.initState();
    _parameters = ServiceParameterEditors(widget.service.variables);
    final taken = {
      ...ref.read(elpVmNamesProvider),
      ...ref.read(deletedVmsProvider),
    };
    while (true) {
      final name = prefixedServiceInstanceName(
        widget.service.id,
        generatePetname(),
      );
      if (!taken.contains(name)) {
        _generatedName = name;
        break;
      }
    }
  }

  @override
  void dispose() {
    _parameters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = widget.service;
    final branding = serviceBranding(service.id, service: service);
    final randomName = _generatedName;
    final vmNames = ref.watch(elpVmNamesProvider);
    final deletedVms = ref.watch(deletedVmsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final intentNames = ref.watch(intentNamesProvider);

    final minDisk = serviceDiskBytes(service);

    final intentDropdown = Dropdown<String?>(
      label: 'Composition',
      width: 360,
      value: _selectedIntent,
      onChanged: (value) => setState(() {
        _selectedIntent = value;
        _error = null;
      }),
      items: {
        null: 'None (standalone instance)',
        _createNewIntentValue: '+ Create new composition...',
        for (final existingIntent in intentNames)
          existingIntent: existingIntent,
      },
    );

    final intentSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap, not Row: dropdown + new-name + role can add up to more than the dialog's
        // width (each is a fixed 360px), which previously pushed the last field(s) off
        // screen instead of onto their own line.
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            intentDropdown,
            if (_selectedIntent == _createNewIntentValue)
              SpecInput(
                label: 'New composition name',
                hint: 'e.g. test-app-1',
                initialValue: _newIntentName,
                onSaved: (value) => _newIntentName = value ?? '',
                width: 360,
              ),
            if (_selectedIntent != null)
              SpecInput(
                label: 'Role in composition',
                helper:
                    'What this service is within the composition (e.g. "redis").',
                hint: 'e.g. redis',
                initialValue: _intentRole,
                onSaved: (value) => _intentRole = value ?? '',
                width: 360,
              ),
          ],
        ),
      ],
    );

    return AlertDialog(
      title: Row(
        children: [
          ServiceIconBadge(branding: branding, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l10n.serviceDeployTitle(service.displayName)),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            splashRadius: 15,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: CompactLayout.dialogWidth(context, 620),
        // Services expose up to 25 parameters, so the body has to scroll
        // within a bounded box rather than grow the dialog off-screen.
        height: min(620, MediaQuery.of(context).size.height * 0.65),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.always,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(),
                Text(
                  l10n.serviceDeployBody,
                  style: TextStyle(
                    fontFamily: Brand.fontFamily,
                    fontSize: 13,
                    height: 1.35,
                    color: onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 20),
                SpecInput(
                  label: l10n.launchFormNameLabel,
                  autofocus: true,
                  hint: randomName,
                  validator: nameValidator(vmNames, deletedVms, l10n),
                  onSaved: (value) => _request.instanceName =
                      value.isNullOrBlank ? randomName : value!,
                  width: 360,
                ),
                const SizedBox(height: 12),
                CpusSlider(
                  initialValue: serviceCpus(service),
                  onSaved: (value) => _request.numCores = value!,
                ),
                const SizedBox(height: 12),
                RamSlider(
                  initialValue: serviceMemoryBytes(service),
                  min: serviceMemoryBytes(service),
                  onSaved: (value) => _request.memSize = '${value!}B',
                ),
                const SizedBox(height: 12),
                DiskSlider(
                  initialValue: minDisk,
                  min: minDisk,
                  onSaved: (value) => _request.diskSpace = '${value!}B',
                ),
                const SizedBox(height: 12),
                intentSection,
                if (!_parameters.isEmpty) ...[
                  const Divider(height: 40),
                  ServiceParametersForm(editors: _parameters),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const Divider(height: 32),
              ],
            ),
          ),
        ),
      ),
      actions: [
        LaunchPadButton.secondary(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        LaunchPadButton.primary(
          onPressed: _deploy,
          child: Text(l10n.serviceDeployAction),
        ),
      ],
    );
  }

  Future<void> _deploy() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    formState.save();

    final l10n = AppLocalizations.of(context)!;
    final service = widget.service;

    try {
      final gatewayCaPem = await fetchGatewayCaPem();
      _request.cloudInitUserData = renderServiceCloudInit(
        service,
        variables: _parameters.values,
        gatewayCaPem: gatewayCaPem,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = l10n.serviceDeployFailure(
          service.displayName,
          l10n.serviceDeployGatewayCaFailure(gatewayCaUrl, '$error'),
        );
      });
      return;
    }

    if (!mounted) return;

    // Leaving `image` unset launches the daemon's default Ubuntu LTS.
    _request.serviceId = service.id;
    final navigator = Navigator.of(context);
    final destination = serviceInstanceSidebarKey(_request.instanceName);

    final selectedIntent = _selectedIntent;
    final bool started;
    final String successSidebarKey;
    if (selectedIntent == null) {
      ref
          .read(serviceInstanceBindingsProvider.notifier)
          .bind(_request.instanceName, service.id);
      started = await initiateLaunchFlow(
        context,
        ref,
        _request.deepCopy(),
        os: _serviceOs,
        // The dialog already shows the disk size on a slider.
        confirmLargeDisk: false,
        successSidebarKey: destination,
      );
      successSidebarKey = destination;
    } else {
      // The daemon names an intent member "<intent>-<role>" itself, ignoring
      // _request.instanceName, so there's no single service page to jump to
      // here — go to the intent instead.
      started = selectedIntent == _createNewIntentValue
          ? await _deployIntoIntent(newIntentName: _newIntentName.trim())
          : await _deployIntoIntent(existingIntentName: selectedIntent);
      successSidebarKey = IntentsScreen.sidebarKey;
    }
    if (!started || !mounted) return;

    navigator.pop();
    ref.read(sidebarKeyProvider.notifier).set(successSidebarKey);
  }

  /// Deploys this service as a member of an intent — either a brand new one
  /// (via intent_create) or an already-existing one (via intent_add_member)
  /// — instead of a plain launch, mirroring LaunchForm's own
  /// `_launchIntoIntent`. `service_id` is carried on the `IntentMemberRequest`
  /// so the instance is still recognized as a deployed service (its bindings
  /// are set unconditionally in [_deploy]) even though it's grouped into an
  /// intent rather than launched standalone. Pass exactly one of
  /// [newIntentName] or [existingIntentName].
  Future<bool> _deployIntoIntent({
    String? newIntentName,
    String? existingIntentName,
  }) async {
    assert((newIntentName == null) != (existingIntentName == null));

    if (newIntentName != null && newIntentName.isEmpty) {
      setState(() => _error = 'Please provide a name for the new composition.');
      return false;
    }
    if (_intentRole.trim().isEmpty) {
      setState(() => _error = 'Please provide a role for this member.');
      return false;
    }

    try {
      final role = _intentRole.trim();
      final member = buildServiceIntentMember(
        service: widget.service,
        role: role,
        variables: _parameters.values,
        numCores: _request.numCores,
        memSize: _request.memSize,
        diskSpace: _request.diskSpace,
      );
      if (_request.hasCloudInitUserData()) {
        member.cloudInitUserData = _request.cloudInitUserData;
      }

      final grpcClient = ref.read(grpcClientProvider);
      final String intentName;
      final Future<dynamic> op;
      if (newIntentName != null) {
        intentName = newIntentName;
        op = grpcClient.intentCreate(
          IntentCreateRequest(name: intentName, members: [member]),
        );
      } else {
        intentName = existingIntentName!;
        op = grpcClient.intentAddMember(
          IntentAddMemberRequest(name: intentName, members: [member]),
        );
      }

      ref.read(notificationsProvider.notifier).addOperation(
            op,
            loading: 'Adding $role to composition $intentName…',
            onSuccess: (reply) {
              final message = reply?.replyMessage as String?;
              return message?.isNotEmpty == true
                  ? message!
                  : 'Added $role to composition $intentName';
            },
            onError: (error) => '$error',
          );
      await op;

      ref.read(serviceInstanceBindingsProvider.notifier).bind(
            intentMemberInstanceName(intentName, role),
            widget.service.id,
          );
      ref.invalidate(intentsStreamProvider);
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _error = '$error');
      return false;
    }
  }
}

/// Stores a service's rendered cloud-init in the user's named config library
/// so it can be inspected and edited on the Cloud-init screen.
Future<String> saveServiceCloudInit(
  WidgetRef ref,
  MarketplaceService service,
) async {
  final store = await ref.read(cloudInitStoreProvider.future);
  final name = serviceCloudInitName(service);
  final gatewayCaPem = await fetchGatewayCaPem();
  await store.write(
    name,
    renderServiceCloudInit(service, gatewayCaPem: gatewayCaPem),
  );
  ref.invalidate(cloudInitConfigsProvider);
  return name;
}
