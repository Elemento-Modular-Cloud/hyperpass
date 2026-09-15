import 'package:flutter/foundation.dart';

import '../../grpc_client.dart';

/// Host devices the local LLM runner can (or will) dispatch work to.
enum LlmAcceleratorKind { cpu, gpu, mpu }

class LlmAccelerator {
  const LlmAccelerator({
    required this.id,
    required this.kind,
    required this.name,
    required this.detail,
    required this.available,
    this.usableByRunner = true,
  });

  final String id;
  final LlmAcceleratorKind kind;
  final String name;
  final String detail;

  /// Present on this host (detected).
  final bool available;

  /// The current inference backend can actually place layers here.
  final bool usableByRunner;

  bool get selectable => available && usableByRunner;
}

class LlmRunnerSnapshot {
  const LlmRunnerSnapshot({
    required this.backendId,
    required this.backendName,
    required this.backendReady,
    required this.backendDetail,
    required this.accelerators,
  });

  final String backendId;
  final String backendName;
  final bool backendReady;
  final String backendDetail;
  final List<LlmAccelerator> accelerators;

  LlmAccelerator? byId(String id) {
    for (final accelerator in accelerators) {
      if (accelerator.id == id) return accelerator;
    }
    return null;
  }
}

const cpuAcceleratorId = 'cpu';
const gpuAcceleratorId = 'gpu';
const mpuAcceleratorId = 'mpu';

bool isAppleSiliconHost(TargetPlatform platform, String hostArch) {
  final apple =
      platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
  if (!apple) return false;
  final arch = hostArch.toLowerCase();
  return arch.contains('arm') || arch.contains('aarch');
}

LlmRunnerSnapshot probeLlmRunner({
  required DaemonInfoReply? info,
  required ListLlmBackendsReply? backends,
  required TargetPlatform platform,
}) {
  final rows = backends?.backends ?? const <LlmBackendInfo>[];
  final llamacpp = _backend(rows, 'llamacpp');
  final mlx = _backend(rows, 'mlx');
  final cuda = _backend(rows, 'cuda');
  final inference = (llamacpp != null && llamacpp.status == 'ready')
      ? llamacpp
      : (mlx != null && mlx.status == 'ready')
          ? mlx
          : llamacpp ?? mlx;

  final hostArch = info?.hostArch ?? '';
  final appleSilicon = isAppleSiliconHost(platform, hostArch);
  final cpuCount = info?.cpus ?? 0;

  final gpuAvailable = (cuda != null && cuda.status == 'ready') || appleSilicon;
  final gpuName = cuda != null && cuda.status == 'ready'
      ? 'NVIDIA CUDA'
      : appleSilicon
          ? 'Apple GPU (Metal)'
          : 'GPU';
  final gpuDetail = cuda != null && cuda.status == 'ready'
      ? (cuda.detail.isNotEmpty
          ? cuda.detail
          : 'nvidia-smi reported a CUDA device')
      : appleSilicon
          ? 'Metal device on Apple Silicon'
          : 'No GPU reported for this runner';

  return LlmRunnerSnapshot(
    backendId: inference?.id ?? 'llamacpp',
    backendName: inference == null
        ? 'llama.cpp'
        : (inference.name.isEmpty ? inference.id : inference.name),
    backendReady: inference?.status == 'ready',
    backendDetail: inference == null
        ? ''
        : (inference.detail.isNotEmpty ? inference.detail : inference.status),
    accelerators: [
      LlmAccelerator(
        id: cpuAcceleratorId,
        kind: LlmAcceleratorKind.cpu,
        name: 'CPU',
        detail: cpuCount > 0
            ? (hostArch.isEmpty
                ? '$cpuCount cores'
                : '$cpuCount cores · $hostArch')
            : (hostArch.isEmpty ? 'Host processor' : hostArch),
        available: true,
      ),
      LlmAccelerator(
        id: gpuAcceleratorId,
        kind: LlmAcceleratorKind.gpu,
        name: gpuName,
        detail: gpuDetail,
        available: gpuAvailable,
      ),
      LlmAccelerator(
        id: mpuAcceleratorId,
        kind: LlmAcceleratorKind.mpu,
        name: appleSilicon ? 'Apple Neural Engine' : 'MPU',
        detail: appleSilicon
            ? 'Present on Apple Silicon; not dispatched by this runner yet'
            : 'No MPU/NPU reported for this host',
        available: appleSilicon,
        usableByRunner: false,
      ),
    ],
  );
}

/// One accelerator at a time until combining is licensed.
Set<String> defaultSelectedAcceleratorIds(
    Iterable<LlmAccelerator> accelerators) {
  LlmAccelerator? gpu;
  LlmAccelerator? cpu;
  for (final accelerator in accelerators) {
    if (!accelerator.selectable) continue;
    if (accelerator.kind == LlmAcceleratorKind.gpu) gpu ??= accelerator;
    if (accelerator.kind == LlmAcceleratorKind.cpu) cpu ??= accelerator;
  }
  if (gpu != null) return {gpu.id};
  if (cpu != null) return {cpu.id};
  return {};
}

/// Radio-select when [canCombine] is false; toggle-add when true.
Set<String> applyAcceleratorTap({
  required Set<String> selected,
  required LlmAccelerator accelerator,
  required bool canCombine,
}) {
  if (!accelerator.selectable) return selected;
  if (!canCombine) return {accelerator.id};
  if (selected.contains(accelerator.id)) {
    if (selected.length <= 1) return selected;
    return {...selected}..remove(accelerator.id);
  }
  return {...selected, accelerator.id};
}

Set<String> allSelectableAcceleratorIds(Iterable<LlmAccelerator> accelerators) {
  return {
    for (final accelerator in accelerators)
      if (accelerator.selectable) accelerator.id,
  };
}

/// Maps the Runner window selection onto llama.cpp GPU offload.
String gpuOffloadForRunner({
  required Iterable<String> selectedIds,
  required Iterable<LlmAccelerator> accelerators,
}) {
  final selected = selectedIds.toSet();
  for (final accelerator in accelerators) {
    if (selected.contains(accelerator.id) &&
        accelerator.kind == LlmAcceleratorKind.gpu) {
      return 'auto';
    }
  }
  return 'cpu';
}

LlmBackendInfo? _backend(Iterable<LlmBackendInfo> rows, String id) {
  for (final row in rows) {
    if (row.id == id) return row;
  }
  return null;
}
