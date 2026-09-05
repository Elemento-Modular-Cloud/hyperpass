import 'dart:math';

import 'package:basics/basics.dart';
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand.dart';
import '../catalogue/launch_form.dart';
import '../cloud_init/cloud_init_store.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../vm_details/cpus_slider.dart';
import '../vm_details/disk_slider.dart';
import '../vm_details/mapping_slider.dart';
import '../vm_details/ram_slider.dart';
import '../vm_details/spec_input.dart';
import 'service_branding.dart';
import 'service_cloud_init.dart';
import 'service_instance_id.dart';
import 'service_library.dart';
import 'service_parameters_form.dart';

/// The services target Ubuntu (docker.io, docker-compose-v2), which is also
/// what the daemon launches when no image is requested.
const _serviceOs = 'Ubuntu';

int serviceCpus(MarketplaceService service) =>
    max(defaultCpus, service.resources.minCpu);

int serviceMemoryBytes(MarketplaceService service) =>
    max(defaultRam, service.resources.minMemoryGb.gibi);

/// Base VM disk plus everything the manifest wants to persist. The rendered
/// cloud-init grows the root filesystem to fill it.
int serviceDiskBytes(MarketplaceService service) =>
    defaultDisk + service.totalStorageGb.gibi;

/// Name used when a service's cloud-init is saved into the user's library.
String serviceCloudInitName(MarketplaceService service) =>
    service.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _parameters = ServiceParameterEditors(widget.service.variables);
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
    final branding = serviceBranding(service.id);
    final randomName = ref.watch(randomNameProvider);
    final vmNames = ref.watch(elpVmNamesProvider);
    final deletedVms = ref.watch(deletedVmsProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final minDisk = serviceDiskBytes(service);

    return AlertDialog(
      shape: const Border(),
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
        width: 620,
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
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
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
      _request.cloudInitUserData = renderServiceCloudInit(
        service,
        variables: _parameters.values,
      );
    } catch (error) {
      setState(() {
        _error = l10n.serviceDeployFailure(service.displayName, '$error');
      });
      return;
    }

    // Leaving `image` unset launches the daemon's default Ubuntu LTS.
    _request.serviceId = service.id;
    ref
        .read(serviceInstanceBindingsProvider.notifier)
        .bind(_request.instanceName, service.id);
    final navigator = Navigator.of(context);
    final destination = serviceInstanceSidebarKey(_request.instanceName);
    final started = await initiateLaunchFlow(
      context,
      ref,
      _request.deepCopy(),
      os: _serviceOs,
      // The dialog already shows the disk size on a slider.
      confirmLargeDisk: false,
      successSidebarKey: destination,
    );
    if (!started) return;

    navigator.pop();
    ref.read(sidebarKeyProvider.notifier).set(destination);
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
  await store.write(name, renderServiceCloudInit(service));
  ref.invalidate(cloudInitConfigsProvider);
  return name;
}
