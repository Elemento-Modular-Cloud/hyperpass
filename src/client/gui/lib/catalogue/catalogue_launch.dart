import 'package:flutter/material.dart' hide ImageInfo;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'launch_form.dart';

void launchCatalogueImage(
  BuildContext context,
  WidgetRef ref,
  ImageInfo image,
) {
  final name = ref.read(randomNameProvider);
  final alias = image.aliases.first;
  final catalogMin = image.minDisk.toInt();
  final launchRequest = LaunchRequest(
    instanceName: name,
    image: alias,
    numCores: defaultCpus,
    memSize: '${defaultRam}B',
    remoteName: image.hasRemoteName() ? image.remoteName : null,
  );
  if (catalogMin > 0) {
    launchRequest.diskSpace = '${diskBytesForImage(image)}B';
  }

  initiateLaunchFlow(
    context,
    ref,
    launchRequest,
    os: image.os,
  );
}

void configureCatalogueImage(WidgetRef ref, ImageInfo image) {
  ref.read(launchingImageProvider.notifier).set(image);
}
