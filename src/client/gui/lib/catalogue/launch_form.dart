import 'dart:async';

import 'package:basics/basics.dart';
import 'package:flutter/material.dart' hide Switch, ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../confirmation_dialog.dart';
import '../ffi.dart';
import '../l10n/app_localizations.dart';
import '../notifications.dart';
import '../overview/recent_activity.dart';
import '../platform/platform.dart';
import '../providers.dart';
import '../sidebar.dart';
import '../switch.dart';
import '../widgets/launchpad_button.dart';
import '../vm_details/cpus_slider.dart';
import '../vm_details/disk_slider.dart';
import '../vm_details/mapping_slider.dart';
import '../vm_details/mount_points.dart';
import '../vm_details/ram_slider.dart';
import '../vm_details/spec_input.dart';
import '../cloud_init/cloud_init_screen.dart';
import '../cloud_init/cloud_init_store.dart';
import '../dropdown.dart';

class LaunchingImageNotifier extends Notifier<ImageInfo> {
  @override
  ImageInfo build() {
    return ImageInfo();
  }

  void set(ImageInfo imageInfo) {
    state = imageInfo;
  }
}

final launchingImageProvider =
    NotifierProvider<LaunchingImageNotifier, ImageInfo>(
  LaunchingImageNotifier.new,
);

class CloudInitLaunchRequiredNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setRequired(bool value) => state = value;

  void clear() => state = false;
}

final cloudInitLaunchRequiredProvider =
    NotifierProvider<CloudInitLaunchRequiredNotifier, bool>(
  CloudInitLaunchRequiredNotifier.new,
);

class SelectedCloudInitNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? name) => state = name;

  void clear() => state = null;
}

final selectedCloudInitProvider =
    NotifierProvider<SelectedCloudInitNotifier, String?>(
  SelectedCloudInitNotifier.new,
);

final randomNameProvider = Provider.autoDispose(
  (ref) => generatePetname(ref.watch(elpVmNamesProvider)),
);

String imageName(ImageInfo imageInfo) {
  final result = '${imageInfo.os} ${imageInfo.release}';
  return imageInfo.aliases.any((a) => RegExp(r'\bcore\d{0,2}\b').hasMatch(a))
      ? result
      : '$result ${imageInfo.codename}';
}

final defaultCpus = 1;
final defaultRam = 1.gibi;
final defaultDisk = 5.gibi;

bool _isCoreImage(ImageInfo imageInfo) {
  return imageInfo.aliases.any((a) => RegExp(r'\bcore\d{0,2}\b').hasMatch(a));
}

int diskBytesForImage(ImageInfo image) {
  final fallback = _isCoreImage(image) ? 1.gibi : defaultDisk;
  final catalogMin = image.minDisk.toInt();
  return catalogMin > fallback ? catalogMin : fallback;
}

String formatDiskSize(int bytes) {
  final gibi = bytes / 1.gibi;
  if ((gibi - gibi.round()).abs() < 0.05) {
    return '${gibi.round()} GiB';
  }
  return '${gibi.toStringAsFixed(1)} GiB';
}

int? diskBytesFromRequest(LaunchRequest request) {
  if (!request.hasDiskSpace()) return null;
  final value = request.diskSpace;
  if (value.endsWith('B') &&
      !value.endsWith('KiB') &&
      !value.endsWith('MiB') &&
      !value.endsWith('GiB')) {
    return int.tryParse(value.substring(0, value.length - 1));
  }
  return int.tryParse(value);
}

class LaunchForm extends ConsumerStatefulWidget {
  const LaunchForm({super.key});

  @override
  ConsumerState<LaunchForm> createState() => _LaunchFormState();
}

class _LaunchFormState extends ConsumerState<LaunchForm> {
  final formKey = GlobalKey<FormState>();
  final mountFormKey = GlobalKey<FormState>();
  final launchRequest = LaunchRequest();
  final mountRequests = <MountRequest>[];
  var addingMount = false;
  final scrollController = ScrollController();
  final cloudInitSectionKey = GlobalKey();
  String? _cloudInitError;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  final bridgedNetworkProvider = daemonSettingProvider('local.bridged-network');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final imageInfo = ref.watch(launchingImageProvider);
    final randomName = ref.watch(randomNameProvider);
    final cloudInitRequired = ref.watch(cloudInitLaunchRequiredProvider);
    final selectedCloudInit = ref.watch(selectedCloudInitProvider);
    final cloudInitConfigs = ref.watch(cloudInitConfigsProvider).when(
          data: (configs) => configs,
          loading: () => const <CloudInitConfigInfo>[],
          error: (_, __) => const <CloudInitConfigInfo>[],
        );

    if (cloudInitRequired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = cloudInitSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 250),
            alignment: 0.1,
          );
        }
      });
    }
    final vmNames = ref.watch(elpVmNamesProvider);
    final deletedVms = ref.watch(deletedVmsProvider);
    final networksAsync = ref.watch(networksProvider);
    final networks = networksAsync.when(
      data: (data) => data,
      loading: () => const <String>{},
      error: (_, __) => const <String>{},
    );
    final bridgedNetworkSetting = ref.watch(bridgedNetworkProvider).when(
          data: (data) => data,
          loading: () => null,
          error: (_, __) => null,
        );

    final closeButton = IconButton(
      icon: const Icon(Icons.close),
      onPressed: () => Scaffold.of(context).closeEndDrawer(),
    );

    final nameInput = SpecInput(
      label: l10n.launchFormNameLabel,
      autofocus: true,
      helper: l10n.launchFormNameHelper,
      hint: randomName,
      validator: nameValidator(vmNames, deletedVms, l10n),
      onSaved: (value) => launchRequest.instanceName =
          value.isNullOrBlank ? randomName : value!,
      width: 360,
    );

    final chosenImageName = Text(
      imageName(imageInfo),
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w300),
    );

    final cpusSlider = CpusSlider(
      initialValue: defaultCpus,
      onSaved: (value) => launchRequest.numCores = value!,
    );

    // Determine minimums based on image type
    final isCore = _isCoreImage(imageInfo);
    final minRam = isCore ? 512.mebi : 1024.mebi;
    final minDisk = diskBytesForImage(imageInfo);

    final memorySlider = RamSlider(
      initialValue: defaultRam,
      min: minRam,
      onSaved: (value) => launchRequest.memSize = '${value!}B',
    );

    final diskSlider = DiskSlider(
      initialValue: minDisk,
      min: minDisk,
      onSaved: (value) => launchRequest.diskSpace = '${value!}B',
    );

    final validBridgedNetwork = networks.contains(bridgedNetworkSetting);
    final bridgedSwitch = FormField<bool>(
      enabled: validBridgedNetwork,
      initialValue: false,
      onSaved: (value) {
        if (value!) {
          launchRequest.networkOptions.add(
            LaunchRequest_NetworkOptions(id: 'bridged'),
          );
        }
      },
      builder: (field) {
        final message = networks.isEmpty
            ? l10n.bridgeNoNetworks
            : validBridgedNetwork
                ? l10n.launchFormBridgeConnect
                : l10n.launchFormBridgeNoValidNetwork;

        return Switch(
          label: message,
          value: validBridgedNetwork ? field.value! : false,
          enabled: validBridgedNetwork,
          onChanged: field.didChange,
        );
      },
    );

    final mountPointsView = MountPointsView(
      allowDelete: true,
      mounts: mountRequests.map(
        (r) => MountPaths(
          sourcePath: r.sourcePath,
          targetPath: r.targetPaths.first.targetPath,
        ),
      ),
      onDelete: (mountPaths) => setState(() {
        mountRequests.removeWhere(
          (r) =>
              r.sourcePath == mountPaths.sourcePath &&
              r.targetPaths.first.targetPath == mountPaths.targetPath,
        );
      }),
    );

    final addMountButton = OutlinedButton(
      onPressed: () => setState(() {
        addingMount = true;
        Timer(100.milliseconds, () {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: 200.milliseconds,
            curve: Curves.ease,
          );
        });
      }),
      child: Text(l10n.mountsAddMount),
    );

    final saveMountButton = LaunchPadButton.primary(
      onPressed: () {
        final mountFormState = mountFormKey.currentState;
        if (mountFormState == null) return;
        if (!mountFormState.validate()) return;
        mountFormState.save();
      },
      child: Text(l10n.commonSave),
    );

    final cancelMountButton = OutlinedButton(
      onPressed: () => setState(() => addingMount = false),
      child: Text(l10n.commonCancel),
    );

    final editableMountPoint = EditableMountPoint(
      existingTargets: mountRequests.map((r) => r.targetPaths.first.targetPath),
      initialSource:
          mountRequests.any((r) => r.sourcePath == mpPlatform.homeDirectory)
              ? null
              : mpPlatform.homeDirectory,
      onSaved: (request) => setState(() {
        mountRequests.add(request);
        addingMount = false;
      }),
    );

    final mountForm = Form(
      key: mountFormKey,
      child: Column(
        children: [
          editableMountPoint,
          const SizedBox(height: 16),
          Row(
            children: [
              saveMountButton,
              const SizedBox(width: 16),
              cancelMountButton,
            ],
          ),
        ],
      ),
    );

    final formBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l10n.launchFormTitle, style: const TextStyle(fontSize: 24)),
            const Spacer(),
            closeButton,
          ],
        ),
        const SizedBox(height: 20),
        Text(l10n.launchFormImageLabel, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        chosenImageName,
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [nameInput, const Spacer()],
        ),
        const Divider(height: 60),
        SizedBox(
          height: 50,
          child:
              Text(l10n.resourcesTitle, style: const TextStyle(fontSize: 24)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cpusSlider),
            const SizedBox(width: 86),
            Expanded(child: memorySlider),
            const SizedBox(width: 86),
            Expanded(child: diskSlider),
          ],
        ),
        const Divider(height: 60),
        SizedBox(
          height: 50,
          child: Text(l10n.bridgeTitle, style: const TextStyle(fontSize: 24)),
        ),
        bridgedSwitch,
        const Divider(height: 60),
        KeyedSubtree(
          key: cloudInitSectionKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 50,
                child: Text(
                  l10n.cloudInitLaunchSectionTitle,
                  style: TextStyle(
                    fontSize: 24,
                    color: cloudInitRequired
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight:
                        cloudInitRequired ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (cloudInitRequired)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l10n.cloudInitLaunchRequired,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Dropdown<String?>(
                value: selectedCloudInit,
                width: 360,
                onChanged: (value) {
                  ref.read(selectedCloudInitProvider.notifier).set(value);
                  setState(() => _cloudInitError = null);
                },
                items: {
                  null: l10n.cloudInitLaunchNone,
                  for (final config in cloudInitConfigs) config.name: config.name,
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Scaffold.of(context).closeEndDrawer();
                  ref
                      .read(sidebarKeyProvider.notifier)
                      .set(CloudInitScreen.sidebarKey);
                },
                child: Text(l10n.cloudInitLaunchManage),
              ),
              if (selectedCloudInit != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Chip(
                    avatar: const Icon(Icons.description_outlined, size: 18),
                    label: Text(l10n.cloudInitLaunchSelected(selectedCloudInit)),
                  ),
                ),
              if (_cloudInitError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _cloudInitError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 60),
        SizedBox(
          height: 50,
          child: Text(l10n.mountsTitle, style: const TextStyle(fontSize: 24)),
        ),
        mountPointsView,
        if (mountRequests.isNotEmpty) const SizedBox(height: 20),
        addingMount ? mountForm : addMountButton,
      ],
    );

    final launchButton = LaunchPadButton.primary(
      onPressed: () => launch(imageInfo),
      child: Text(l10n.commonLaunch),
    );

    final launchWithCloudInitButton = OutlinedButton(
      onPressed: () => launch(imageInfo, requireCloudInit: true),
      child: Text(l10n.cloudInitLaunchButton),
    );

    final launchAndConfigureNextButton = OutlinedButton(
      onPressed: () => launch(imageInfo, configureNext: true),
      child: Text(l10n.launchFormLaunchAndConfigureNext),
    );

    final cancelButton = OutlinedButton(
      onPressed: () => Scaffold.of(context).closeEndDrawer(),
      child: Text(l10n.commonCancel),
    );

    final surface = Theme.of(context).colorScheme.surface;

    return Stack(
      fit: StackFit.loose,
      children: [
        Positioned.fill(
          bottom: 100,
          child: Container(
            alignment: Alignment.topCenter,
            color: surface,
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.always,
              child: SingleChildScrollView(
                clipBehavior: Clip.none,
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: formBody,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            color: surface,
            padding: const EdgeInsets.all(16).copyWith(top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 30),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    launchButton,
                    launchWithCloudInitButton,
                    launchAndConfigureNextButton,
                    cancelButton,
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> launch(
    ImageInfo imageInfo, {
    bool configureNext = false,
    bool requireCloudInit = false,
  }) async {
    final formState = formKey.currentState;
    if (formState == null) return;
    final mountFormState = mountFormKey.currentState;

    if (!formState.validate()) return;
    if (!(mountFormState?.validate() ?? true)) return;

    final selectedCloudInit = ref.read(selectedCloudInitProvider);
    if (requireCloudInit && selectedCloudInit == null) {
      setState(() {
        _cloudInitError =
            AppLocalizations.of(context)!.cloudInitLaunchRequired;
      });
      ref.read(cloudInitLaunchRequiredProvider.notifier).setRequired(true);
      final ctx = cloudInitSectionKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
        );
      }
      return;
    }

    mountFormState?.save();
    formState.save();

    if (selectedCloudInit != null) {
      try {
        final store = await ref.read(cloudInitStoreProvider.future);
        final contents = await store.read(selectedCloudInit);
        launchRequest.cloudInitUserData = contents;
      } catch (error) {
        setState(() => _cloudInitError = '$error');
        return;
      }
    } else {
      launchRequest.clearCloudInitUserData();
    }

    launchRequest.image = imageInfo.aliases.first;
    if (imageInfo.hasRemoteName()) {
      launchRequest.remoteName = imageInfo.remoteName;
    }

    // Stale catalogs may lack min_disk; omit explicit disk so the daemon
    // applies max(5G, qemu virtual-size), matching CLI without --disk.
    if (imageInfo.minDisk.toInt() == 0) {
      final requested = diskBytesFromRequest(launchRequest);
      if (requested == null || requested <= diskBytesForImage(imageInfo)) {
        launchRequest.clearDiskSpace();
      }
    }

    for (final mountRequest in mountRequests) {
      mountRequest.targetPaths.first.instanceName = launchRequest.instanceName;
    }

    final started = await initiateLaunchFlow(
      context,
      ref,
      launchRequest.deepCopy(),
      mountRequests: mountRequests.map((r) => r.deepCopy()).toList(),
      os: imageInfo.os,
    );

    if (!started || !mounted) return;

    ref.read(cloudInitLaunchRequiredProvider.notifier).clear();

    if (!configureNext) {
      Scaffold.of(context).closeEndDrawer();
      ref
          .read(sidebarKeyProvider.notifier)
          .set(elpVm(launchRequest.instanceName).sidebarKey);
    }
  }
}

Future<bool> initiateLaunchFlow(
  BuildContext context,
  WidgetRef ref,
  LaunchRequest launchRequest, {
  List<MountRequest> mountRequests = const [],
  String os = '',
  bool confirmLargeDisk = true,
  String? successSidebarKey,
}) async {
  final disk = diskBytesFromRequest(launchRequest);
  if (confirmLargeDisk && disk != null && disk > defaultDisk) {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ConfirmationDialog(
        title: l10n.launchDiskConfirmTitle,
        body: Text(l10n.launchDiskConfirmBody(formatDiskSize(disk))),
        actionText: l10n.commonContinue,
        onAction: () => Navigator.pop(dialogContext, true),
        inactionText: l10n.commonCancel,
        onInaction: () => Navigator.pop(dialogContext, false),
      ),
    );
    if (confirmed != true) return false;
  }

  final grpcClient = ref.read(grpcClientProvider);
  final launchingVmsNotifier = ref.read(launchingVmsProvider.notifier);

  launchingVmsNotifier.add(launchRequest, os: os);
  final cancelCompleter = Completer<void>();
  final launchStream = grpcClient
      .launch(
        launchRequest,
        mountRequests: mountRequests,
        cancel: cancelCompleter.future,
      )
      .doOnDone(() => launchingVmsNotifier.remove(launchRequest.instanceName));

  final notification = LaunchingNotification(
    name: launchRequest.instanceName,
    cancelCompleter: cancelCompleter,
    stream: launchStream,
    successSidebarKey: successSidebarKey,
  );

  ref.read(notificationsProvider.notifier).add(notification);
  ref.read(recentActivityProvider.notifier).record(
        title: 'Launching ${launchRequest.instanceName}',
        detail: os.isEmpty ? 'VM' : os,
      );
  return true;
}

FormFieldValidator<String> nameValidator(
  Iterable<String> existingNames,
  Iterable<String> deletedNames,
  AppLocalizations l10n,
) {
  return (String? value) {
    if (value!.isEmpty) {
      return null;
    }
    if (value.length < 2) {
      return l10n.usagePrimaryNameErrorTooShort;
    }
    if (RegExp(r'[^A-Za-z0-9\-]').hasMatch(value)) {
      return l10n.launchFormNameErrorInvalidChars;
    }
    if (RegExp(r'^[^A-Za-z]').hasMatch(value)) {
      return l10n.usagePrimaryNameErrorStartLetter;
    }
    if (RegExp(r'[^A-Za-z0-9]$').hasMatch(value)) {
      return l10n.usagePrimaryNameErrorEndChar;
    }
    if (existingNames.contains(value)) {
      return l10n.launchFormNameErrorInUse;
    }
    if (deletedNames.contains(value)) {
      return l10n.launchFormNameErrorDeletedInUse;
    }
    return null;
  };
}
