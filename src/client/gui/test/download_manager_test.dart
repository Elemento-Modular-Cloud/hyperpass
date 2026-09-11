import 'dart:async';
import 'dart:io';

import 'package:elp_gui/downloads/download_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs queued downloads one at a time', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final firstGate = Completer<void>();
    final secondStarted = Completer<void>();
    final mgr = container.read(downloadManagerProvider.notifier);

    mgr.enqueue(
      kind: DownloadKind.vmImage,
      label: 'A',
      dedupKey: 'a',
      execute: (_) => firstGate.future,
    );
    mgr.enqueue(
      kind: DownloadKind.llmModel,
      label: 'B',
      dedupKey: 'b',
      execute: (_) async {
        secondStarted.complete();
      },
    );

    await Future<void>.delayed(Duration.zero);
    var jobs = container.read(downloadManagerProvider);
    expect(jobs, hasLength(2));
    expect(jobs[0].status, DownloadStatus.running);
    expect(jobs[1].status, DownloadStatus.queued);

    firstGate.complete();
    await secondStarted.future;
    jobs = container.read(downloadManagerProvider);
    expect(jobs[0].status, DownloadStatus.done);
    expect(jobs[1].status, DownloadStatus.running);
  });

  test('dedupes an already queued or running job', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final gate = Completer<void>();
    final mgr = container.read(downloadManagerProvider.notifier);

    final first = mgr.enqueue(
      kind: DownloadKind.llmModel,
      label: 'm',
      dedupKey: 'llm:m',
      execute: (_) => gate.future,
    );
    final second = mgr.enqueue(
      kind: DownloadKind.llmModel,
      label: 'm',
      dedupKey: 'llm:m',
      execute: (_) async {},
    );
    expect(second, first);
    expect(container.read(downloadManagerProvider), hasLength(1));
    gate.complete();
  });

  test('POTD job can write a file', () async {
    final dest = File(
      '${Directory.systemTemp.path}/elp-potd-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    addTearDown(() {
      if (dest.existsSync()) dest.deleteSync();
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(downloadManagerProvider.notifier).enqueueAndWait(
          kind: DownloadKind.potd,
          label: 'NASA POTD',
          dedupKey: 'potd:test',
          execute: (controller) async {
            await dest.writeAsString('wallpaper');
            controller.setPath(dest.path);
          },
        );

    expect(dest.existsSync(), isTrue);
    expect(dest.readAsStringSync(), 'wallpaper');
    final job = container.read(downloadManagerProvider).single;
    expect(job.status, DownloadStatus.done);
    expect(job.path, dest.path);
  });

  test('cancelling a queued job finishes it without running', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final mgr = container.read(downloadManagerProvider.notifier);
    final gate = Completer<void>();
    var secondRan = false;

    mgr.enqueue(
      kind: DownloadKind.vmImage,
      label: 'A',
      dedupKey: 'a',
      execute: (_) => gate.future,
    );
    final queuedId = mgr.enqueue(
      kind: DownloadKind.vmImage,
      label: 'B',
      dedupKey: 'b',
      execute: (_) async {
        secondRan = true;
      },
    );

    mgr.cancel(queuedId);
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(secondRan, isFalse);
    final jobs = container.read(downloadManagerProvider);
    expect(jobs[1].status, DownloadStatus.cancelled);
  });
}
