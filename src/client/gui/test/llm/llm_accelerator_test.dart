import 'package:elp_gui/grpc_client.dart';
import 'package:elp_gui/llm/runner/llm_accelerator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('always represents CPU, GPU, and MPU', () {
    final snapshot = probeLlmRunner(
      info: DaemonInfoReply(cpus: 8, hostArch: 'x86_64'),
      backends: ListLlmBackendsReply(),
      platform: TargetPlatform.linux,
    );

    expect(
      snapshot.accelerators.map((a) => a.kind).toList(),
      [LlmAcceleratorKind.cpu, LlmAcceleratorKind.gpu, LlmAcceleratorKind.mpu],
    );
    expect(snapshot.byId(cpuAcceleratorId)!.available, isTrue);
    expect(snapshot.byId(gpuAcceleratorId)!.available, isFalse);
    expect(snapshot.byId(mpuAcceleratorId)!.available, isFalse);
    expect(snapshot.byId(mpuAcceleratorId)!.usableByRunner, isFalse);
  });

  test('Apple Silicon exposes Metal GPU and ANE MPU', () {
    final snapshot = probeLlmRunner(
      info: DaemonInfoReply(cpus: 10, hostArch: 'arm64'),
      backends: ListLlmBackendsReply(
        backends: [
          LlmBackendInfo(
            id: 'llamacpp',
            name: 'llama.cpp (llama-server)',
            status: 'ready',
            detail: 'b1234',
          ),
        ],
      ),
      platform: TargetPlatform.macOS,
    );

    expect(snapshot.backendReady, isTrue);
    expect(snapshot.byId(gpuAcceleratorId)!.available, isTrue);
    expect(snapshot.byId(gpuAcceleratorId)!.usableByRunner, isTrue);
    expect(snapshot.byId(gpuAcceleratorId)!.name, contains('Metal'));
    expect(snapshot.byId(mpuAcceleratorId)!.available, isTrue);
    expect(snapshot.byId(mpuAcceleratorId)!.usableByRunner, isFalse);
    expect(defaultSelectedAcceleratorIds(snapshot.accelerators),
        {gpuAcceleratorId});
  });

  test('CUDA backend marks the GPU available', () {
    final snapshot = probeLlmRunner(
      info: DaemonInfoReply(cpus: 16, hostArch: 'x86_64'),
      backends: ListLlmBackendsReply(
        backends: [
          LlmBackendInfo(id: 'cuda', name: 'NVIDIA CUDA', status: 'ready'),
        ],
      ),
      platform: TargetPlatform.linux,
    );

    expect(snapshot.byId(gpuAcceleratorId)!.available, isTrue);
    expect(snapshot.byId(gpuAcceleratorId)!.name, contains('CUDA'));
    expect(snapshot.byId(mpuAcceleratorId)!.available, isFalse);
  });

  test('tapping another accelerator replaces when combining is locked', () {
    final cpu = LlmAccelerator(
      id: cpuAcceleratorId,
      kind: LlmAcceleratorKind.cpu,
      name: 'CPU',
      detail: '8 cores',
      available: true,
    );
    final gpu = LlmAccelerator(
      id: gpuAcceleratorId,
      kind: LlmAcceleratorKind.gpu,
      name: 'GPU',
      detail: 'Metal',
      available: true,
    );

    expect(
      applyAcceleratorTap(
        selected: {gpuAcceleratorId},
        accelerator: cpu,
        canCombine: false,
      ),
      {cpuAcceleratorId},
    );
  });

  test('tapping adds a second accelerator when combining is licensed', () {
    final cpu = LlmAccelerator(
      id: cpuAcceleratorId,
      kind: LlmAcceleratorKind.cpu,
      name: 'CPU',
      detail: '8 cores',
      available: true,
    );

    expect(
      applyAcceleratorTap(
        selected: {gpuAcceleratorId},
        accelerator: cpu,
        canCombine: true,
      ),
      {gpuAcceleratorId, cpuAcceleratorId},
    );
  });

  test('MPU is not selectable until the runner can dispatch to it', () {
    final mpu = LlmAccelerator(
      id: mpuAcceleratorId,
      kind: LlmAcceleratorKind.mpu,
      name: 'ANE',
      detail: 'present',
      available: true,
      usableByRunner: false,
    );

    expect(
      applyAcceleratorTap(
        selected: {gpuAcceleratorId},
        accelerator: mpu,
        canCombine: true,
      ),
      {gpuAcceleratorId},
    );
  });

  test('gpu offload follows whether the GPU is in the runner', () {
    final accels = [
      LlmAccelerator(
        id: cpuAcceleratorId,
        kind: LlmAcceleratorKind.cpu,
        name: 'CPU',
        detail: '',
        available: true,
      ),
      LlmAccelerator(
        id: gpuAcceleratorId,
        kind: LlmAcceleratorKind.gpu,
        name: 'GPU',
        detail: '',
        available: true,
      ),
    ];

    expect(
      gpuOffloadForRunner(
        selectedIds: {gpuAcceleratorId},
        accelerators: accels,
      ),
      'auto',
    );
    expect(
      gpuOffloadForRunner(
        selectedIds: {cpuAcceleratorId},
        accelerators: accels,
      ),
      'cpu',
    );
  });
}
