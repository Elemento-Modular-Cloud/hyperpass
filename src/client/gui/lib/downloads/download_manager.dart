import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

enum DownloadKind { vmImage, llmModel, llmRuntime, potd }

enum DownloadStatus { queued, running, done, error, cancelled }

typedef DownloadExecutor = Future<void> Function(DownloadController controller);

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.kind,
    required this.label,
    required this.dedupKey,
    this.status = DownloadStatus.queued,
    this.percent = 0,
    this.error = '',
    this.path = '',
    this.modelId = '',
    this.quant = '',
    this.hfRepo = '',
  });

  final String id;
  final DownloadKind kind;
  final String label;
  final String dedupKey;
  final DownloadStatus status;
  final int percent;
  final String error;
  final String path;
  final String modelId;
  final String quant;
  final String hfRepo;

  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.running;

  DownloadJob copyWith({
    DownloadStatus? status,
    int? percent,
    String? error,
    String? path,
  }) {
    return DownloadJob(
      id: id,
      kind: kind,
      label: label,
      dedupKey: dedupKey,
      status: status ?? this.status,
      percent: percent ?? this.percent,
      error: error ?? this.error,
      path: path ?? this.path,
      modelId: modelId,
      quant: quant,
      hfRepo: hfRepo,
    );
  }
}

class DownloadController {
  DownloadController(
    this._onPercent,
    this._onPath,
    this._cancelled,
    this._whenCancelled,
  );

  final void Function(int percent) _onPercent;
  final void Function(String path) _onPath;
  final ValueGetter<bool> _cancelled;
  final Future<void> _whenCancelled;

  bool get isCancelled => _cancelled();

  Future<void> get whenCancelled => _whenCancelled;

  void setPercent(int percent) => _onPercent(percent.clamp(0, 100));

  void setPath(String path) => _onPath(path);
}

class _PendingDownload {
  _PendingDownload(this.execute);

  final DownloadExecutor execute;
  final cancelCompleter = Completer<void>();
  final doneCompleter = Completer<void>();
}

class DownloadManager extends Notifier<List<DownloadJob>> {
  Future<void>? _pump;
  final _pending = <String, _PendingDownload>{};

  @override
  List<DownloadJob> build() => const [];

  int get activeCount => state.where((j) => j.isActive).length;

  String enqueue({
    required DownloadKind kind,
    required String label,
    required String dedupKey,
    required DownloadExecutor execute,
    String modelId = '',
    String quant = '',
    String hfRepo = '',
  }) {
    for (final job in state) {
      if (job.dedupKey == dedupKey && job.isActive) return job.id;
    }

    final id = '${kind.name}_${dedupKey}_${DateTime.now().microsecondsSinceEpoch}';
    _pending[id] = _PendingDownload(execute);
    state = [
      ...state,
      DownloadJob(
        id: id,
        kind: kind,
        label: label,
        dedupKey: dedupKey,
        modelId: modelId,
        quant: quant,
        hfRepo: hfRepo,
      ),
    ];
    _pump ??= _run();
    return id;
  }

  Future<void> enqueueAndWait({
    required DownloadKind kind,
    required String label,
    required String dedupKey,
    required DownloadExecutor execute,
  }) {
    for (final job in state) {
      if (job.dedupKey == dedupKey && job.isActive) {
        return _pending[job.id]?.doneCompleter.future ?? Future.value();
      }
    }
    final id = enqueue(
      kind: kind,
      label: label,
      dedupKey: dedupKey,
      execute: execute,
    );
    return _pending[id]?.doneCompleter.future ?? Future.value();
  }

  void cancel(String id) {
    DownloadJob? job;
    for (final candidate in state) {
      if (candidate.id == id) {
        job = candidate;
        break;
      }
    }
    final pending = _pending[id];
    if (pending != null && !pending.cancelCompleter.isCompleted) {
      pending.cancelCompleter.complete();
    }
    _patch(id, (j) {
      if (!j.isActive) return j;
      return j.copyWith(status: DownloadStatus.cancelled);
    });
    // Queued jobs never enter [_run], so finish them here.
    if (job?.status == DownloadStatus.queued) {
      if (pending != null && !pending.doneCompleter.isCompleted) {
        pending.doneCompleter.complete();
      }
      _pending.remove(id);
    }
  }

  void _patch(String id, DownloadJob Function(DownloadJob) update) {
    state = [
      for (final job in state)
        if (job.id == id) update(job) else job,
    ];
  }

  Future<void> _run() async {
    try {
      while (true) {
        final pendingJobs =
            state.where((j) => j.status == DownloadStatus.queued).toList();
        if (pendingJobs.isEmpty) return;
        final job = pendingJobs.first;
        final pending = _pending[job.id];
        if (pending == null) {
          _patch(job.id, (j) => j.copyWith(status: DownloadStatus.error));
          continue;
        }
        _patch(job.id, (j) => j.copyWith(status: DownloadStatus.running));
        try {
          await pending.execute(
            DownloadController(
              (percent) => _patch(job.id, (j) => j.copyWith(percent: percent)),
              (path) => _patch(job.id, (j) => j.copyWith(path: path)),
              () => pending.cancelCompleter.isCompleted,
              pending.cancelCompleter.future,
            ),
          );
          final current = state.firstWhere((j) => j.id == job.id);
          if (current.status != DownloadStatus.cancelled) {
            _patch(
              job.id,
              (j) => j.copyWith(status: DownloadStatus.done, percent: 100),
            );
          }
          if (!pending.doneCompleter.isCompleted) {
            pending.doneCompleter.complete();
          }
        } catch (e) {
          _patch(
            job.id,
            (j) => j.copyWith(status: DownloadStatus.error, error: '$e'),
          );
          if (!pending.doneCompleter.isCompleted) {
            pending.doneCompleter.completeError(e);
          }
        } finally {
          _pending.remove(job.id);
        }
      }
    } finally {
      _pump = null;
      if (state.any((j) => j.status == DownloadStatus.queued)) {
        _pump = _run();
      }
    }
  }
}

final downloadManagerProvider =
    NotifierProvider<DownloadManager, List<DownloadJob>>(DownloadManager.new);

Future<void> downloadUrlToFile(
  String url,
  File dest, {
  void Function(int percent)? onProgress,
  bool Function()? isCancelled,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    await dest.parent.create(recursive: true);
    final sink = dest.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;
    await for (final chunk in response.stream) {
      if (isCancelled?.call() ?? false) {
        await sink.close();
        if (dest.existsSync()) dest.deleteSync();
        return;
      }
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress?.call(((100 * received) / total).round());
      }
    }
    await sink.close();
    onProgress?.call(100);
  } finally {
    client.close();
  }
}
