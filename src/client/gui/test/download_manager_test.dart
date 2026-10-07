import 'dart:async';
import 'dart:io';

import 'package:elp_gui/downloads/download_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs queued downloads in parallel', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
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
        await secondGate.future;
      },
    );

    await secondStarted.future;
    final jobs = container.read(downloadManagerProvider);
    expect(jobs, hasLength(2));
    expect(jobs[0].status, DownloadStatus.running);
    expect(jobs[1].status, DownloadStatus.running);

    firstGate.complete();
    secondGate.complete();
    await Future<void>.delayed(Duration.zero);
    final done = container.read(downloadManagerProvider);
    expect(done[0].status, DownloadStatus.done);
    expect(done[1].status, DownloadStatus.done);
  });

  test('caps concurrency and drains the queue', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final mgr = container.read(downloadManagerProvider.notifier);

    final gates = List.generate(maxConcurrentDownloads + 1, (_) => Completer<void>());
    final started = List.generate(maxConcurrentDownloads + 1, (_) => Completer<void>());

    for (var i = 0; i < gates.length; i++) {
      final index = i;
      mgr.enqueue(
        kind: DownloadKind.llmModel,
        label: 'm$index',
        dedupKey: 'm$index',
        execute: (_) async {
          started[index].complete();
          await gates[index].future;
        },
      );
    }

    await Future.wait(started.take(maxConcurrentDownloads).map((c) => c.future));
    await Future<void>.delayed(Duration.zero);

    var jobs = container.read(downloadManagerProvider);
    expect(
      jobs.where((j) => j.status == DownloadStatus.running),
      hasLength(maxConcurrentDownloads),
    );
    expect(
      jobs.where((j) => j.status == DownloadStatus.queued),
      hasLength(1),
    );
    expect(started.last.isCompleted, isFalse);

    for (final gate in gates.take(maxConcurrentDownloads)) {
      gate.complete();
    }
    await started.last.future;
    jobs = container.read(downloadManagerProvider);
    expect(jobs.last.status, DownloadStatus.running);

    gates.last.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(downloadManagerProvider).every((j) => j.status == DownloadStatus.done),
      isTrue,
    );
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
    final gates = List.generate(maxConcurrentDownloads, (_) => Completer<void>());
    var overflowRan = false;

    for (var i = 0; i < maxConcurrentDownloads; i++) {
      final index = i;
      mgr.enqueue(
        kind: DownloadKind.vmImage,
        label: 'A$index',
        dedupKey: 'a$index',
        execute: (_) => gates[index].future,
      );
    }
    final queuedId = mgr.enqueue(
      kind: DownloadKind.vmImage,
      label: 'overflow',
      dedupKey: 'overflow',
      execute: (_) async {
        overflowRan = true;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(downloadManagerProvider).last.status,
      DownloadStatus.queued,
    );

    mgr.cancel(queuedId);
    for (final gate in gates) {
      gate.complete();
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(overflowRan, isFalse);
    final jobs = container.read(downloadManagerProvider);
    expect(jobs.last.status, DownloadStatus.cancelled);
  });
}
