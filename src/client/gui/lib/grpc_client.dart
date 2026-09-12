import 'dart:async';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart' hide RpcClient;
import 'package:rxdart/rxdart.dart';

import 'logger.dart';
import 'daemon_source.dart';
import 'providers.dart';
import 'update_available.dart';

export 'generated/multipass.pbgrpc.dart';

typedef Status = InstanceStatus_Status;
typedef VmInfo = DetailedInfoItem;
typedef ImageInfo = FindReply_ImageInfo;
typedef MountPaths = MountInfo_MountPaths;
typedef RpcMessage = GeneratedMessage;

class TaggedVmInfo {
  final VmId id;
  final DetailedInfoItem info;

  const TaggedVmInfo({required this.id, required this.info});

  String get name => id.name;
  DaemonSource get source => id.source;
  InstanceStatus get instanceStatus => info.instanceStatus;
  InstanceDetails get instanceInfo => info.instanceInfo;
  String get memoryTotal => info.memoryTotal;
  String get diskTotal => info.diskTotal;
  String get cpuCount => info.cpuCount;
}

extension on RpcMessage {
  String get repr => '$runtimeType${toProto3Json()}';
}

void checkForUpdate(RpcMessage message) {
  final updateInfo = switch (message) {
    LaunchReply launchReply => launchReply.updateInfo,
    InfoReply infoReply => infoReply.updateInfo,
    ListReply listReply => listReply.updateInfo,
    NetworksReply networksReply => networksReply.updateInfo,
    StartReply startReply => startReply.updateInfo,
    RestartReply restartReply => restartReply.updateInfo,
    VersionReply versionReply => versionReply.updateInfo,
    _ => UpdateInfo(),
  };

  providerContainer.read(updateProvider.notifier).set(updateInfo);
}

void Function(StreamNotification<RpcMessage>) logGrpc(RpcMessage request) {
  return (notification) {
    switch (notification.kind) {
      case NotificationKind.data:
        final reply = notification.requireDataValue.deepCopy();
        if (reply is SSHInfoReply) {
          for (final info in reply.sshInfo.values) {
            info.privKeyBase64 = '*hidden*';
          }
        }
        if (reply is LaunchReply) {
          final percent = reply.launchProgress.percentComplete;
          if (!['0', '100', '-1'].contains(percent)) return;
        }
        logger.i('${request.repr} received ${reply.repr}');
      case NotificationKind.error:
        final es = notification.errorAndStackTraceOrNull;
        logger.e(
          '${request.repr} received an error',
          error: es?.error,
          stackTrace: es?.stackTrace,
        );
      case NotificationKind.done:
        logger.i('${request.repr} is done');
    }
  };
}

class GrpcClient {
  final RpcClient _client;

  GrpcClient(this._client);

  Stream<Either<LaunchReply, MountReply>?> launch(
    LaunchRequest request, {
    List<MountRequest> mountRequests = const [],
    Future<void>? cancel,
  }) async* {
    logger.i('Sent ${request.repr}');
    final launchReplyStream = _client.launch(Stream.value(request));
    cancel?.then((_) => launchReplyStream.cancel());
    final launchStream = launchReplyStream
        .doOnData(checkForUpdate)
        .doOnEach(logGrpc(request))
        .map(Either<LaunchReply, MountReply>.left);
    await for (final launchReply in launchStream) {
      yield launchReply;
    }
    for (final mountRequest in mountRequests) {
      logger.i('Sent ${mountRequest.repr}');
      yield* _client
          .mount(Stream.value(mountRequest))
          .doOnEach(logGrpc(mountRequest))
          .map((Either<LaunchReply, MountReply>.right));
    }
  }

  Future<Rep?> doRpc<Req extends RpcMessage, Rep extends RpcMessage>(
    ResponseStream<Rep> Function(Stream<Req> request) action,
    Req request, {
    bool checkUpdates = false,
    bool log = true,
  }) {
    if (log) logger.i('Sent ${request.repr}');
    Stream<Rep> replyStream = action(Stream.value(request));
    if (checkUpdates) replyStream = replyStream.doOnData(checkForUpdate);
    if (log) replyStream = replyStream.doOnEach(logGrpc(request));
    return replyStream.lastOrNull;
  }

  Future<StartReply?> start(Iterable<String> names) {
    return doRpc(
      _client.start,
      StartRequest(instanceNames: InstanceNames(instanceName: names)),
      checkUpdates: true,
    );
  }

  Future<StopReply?> stop(Iterable<String> names) {
    return doRpc(
      _client.stop,
      StopRequest(instanceNames: InstanceNames(instanceName: names)),
    );
  }

  Future<SuspendReply?> suspend(Iterable<String> names) {
    return doRpc(
      _client.suspend,
      SuspendRequest(instanceNames: InstanceNames(instanceName: names)),
    );
  }

  Future<RestartReply?> restart(Iterable<String> names) {
    return doRpc(
      _client.restart,
      RestartRequest(instanceNames: InstanceNames(instanceName: names)),
      checkUpdates: true,
    );
  }

  Future<DeleteReply?> delete(Iterable<String> names) {
    return doRpc(
      _client.delet,
      DeleteRequest(
        instanceSnapshotPairs: names.map(
          (name) => InstanceSnapshotPair(instanceName: name),
        ),
      ),
    );
  }

  Future<RecoverReply?> recover(Iterable<String> names) {
    return doRpc(
      _client.recover,
      RecoverRequest(instanceNames: InstanceNames(instanceName: names)),
    );
  }

  Future<DeleteReply?> purge(Iterable<String> names) {
    return doRpc(
      _client.delet,
      DeleteRequest(
        purge: true,
        instanceSnapshotPairs: names.map(
          (name) => InstanceSnapshotPair(instanceName: name),
        ),
      ),
    );
  }

  Future<List<VmInfo>> info([Iterable<String> names = const []]) {
    return doRpc(
      _client.info,
      checkUpdates: true,
      log: false,
      InfoRequest(
        instanceSnapshotPairs: names.map(
          (name) => InstanceSnapshotPair(instanceName: name),
        ),
      ),
    ).then((r) => r!.details.toList());
  }

  Future<MountReply?> mount(MountRequest request) {
    return doRpc(_client.mount, request);
  }

  Future<void> umount(String name, [String? path]) {
    return doRpc(
      _client.umount,
      UmountRequest(
        targetPaths: [TargetPathInfo(instanceName: name, targetPath: path)],
      ),
    );
  }

  Future<FindReply> find() {
    return doRpc(
      _client.find,
      FindRequest(),
    ).then((r) => r!);
  }

  Future<List<NetInterface>> networks() {
    return doRpc(
      _client.networks,
      NetworksRequest(),
      checkUpdates: true,
    ).then((r) => r!.interfaces);
  }

  Future<String> version() {
    return doRpc(
      _client.version,
      VersionRequest(),
      checkUpdates: true,
    ).then((r) => r!.version);
  }

  Future<String> get(String key) {
    return doRpc(_client.get, GetRequest(key: key)).then((r) => r!.value);
  }

  Future<void> set(String key, String value) {
    return doRpc(_client.set, SetRequest(key: key, val: value));
  }

  Future<SSHInfo?> sshInfo(String name) {
    return doRpc(
      _client.ssh_info,
      SSHInfoRequest(instanceName: [name]),
    ).then((r) => r!.sshInfo[name]);
  }

  Future<DaemonInfoReply> daemonInfo() {
    return doRpc(_client.daemon_info, DaemonInfoRequest(), log: false).then((r) => r!);
  }

  Future<FindModelsReply> findModels({
    int limit = 10,
    String useCase = '',
    String minFit = '',
    String runtime = '',
    String query = '',
    bool includeTooTight = true,
    int offset = 0,
    bool recommendOnly = false,
  }) {
    return doRpc(
      _client.find_models,
      FindModelsRequest(
        limit: limit,
        useCase: useCase,
        minFit: minFit,
        runtime: runtime,
        query: query,
        includeTooTight: includeTooTight,
        offset: offset,
        recommendOnly: recommendOnly,
      ),
    ).then((r) => r!);
  }

  Future<ListModelsReply> listModels() {
    return doRpc(_client.list_models, ListModelsRequest()).then((r) => r!);
  }

  Future<ListLlmBackendsReply> listLlmBackends() {
    return doRpc(_client.list_llm_backends, ListLlmBackendsRequest()).then((r) => r!);
  }

  Stream<InstallLlmBackendReply> installLlmBackend(String backendId) {
    return _client.install_llm_backend(
      Stream.value(InstallLlmBackendRequest(backendId: backendId)),
    );
  }

  Stream<LoadModelReply> loadModel(
    String modelId, {
    String quant = '',
    int ctxSize = 4096,
    String runtime = '',
    int maxTokens = 0,
    LlmLoadParams? params,
  }) {
    return _client.load_model(
      Stream.value(LoadModelRequest(
        modelId: modelId,
        quant: quant,
        ctxSize: ctxSize,
        runtime: runtime,
        maxTokens: maxTokens,
        params: params,
      )),
    );
  }

  Stream<PullModelReply> pullModel(String modelId, {String quant = '', String hfRepo = ''}) {
    return _client.pull_model(
      Stream.value(PullModelRequest(modelId: modelId, quant: quant, hfRepo: hfRepo)),
    );
  }

  Future<UnloadModelReply> unloadModel(String instanceId) {
    return doRpc(
      _client.unload_model,
      UnloadModelRequest(instanceId: instanceId),
    ).then((r) => r!);
  }

  Future<UnloadModelReply> unloadAllForModel(String modelId) {
    return doRpc(
      _client.unload_model,
      UnloadModelRequest(modelId: modelId),
    ).then((r) => r!);
  }

  Future<DeleteModelReply> deleteModel(String modelId) {
    return doRpc(
      _client.delete_model,
      DeleteModelRequest(modelId: modelId),
    ).then((r) => r!);
  }

  Future<CreateApiKeyReply> createApiKey({
    String label = '',
    String instanceId = '',
    Iterable<String> instanceIds = const [],
  }) {
    return doRpc(
      _client.create_api_key,
      CreateApiKeyRequest(
        label: label,
        instanceId: instanceId,
        instanceIds: instanceIds,
      ),
    ).then((r) => r!);
  }

  Future<ListApiKeysReply> listApiKeys() {
    return doRpc(_client.list_api_keys, ListApiKeysRequest()).then((r) => r!);
  }

  Future<UpdateApiKeyReply> updateApiKey({
    required String id,
    String? label,
    Iterable<String>? instanceIds,
  }) {
    return doRpc(
      _client.update_api_key,
      UpdateApiKeyRequest(
        id: id,
        label: label,
        updateLabel: label != null,
        instanceIds: instanceIds,
        updateInstanceIds: instanceIds != null,
      ),
    ).then((r) => r!);
  }

  Future<RevokeApiKeyReply> revokeApiKey(String id) {
    return doRpc(
      _client.revoke_api_key,
      RevokeApiKeyRequest(id: id),
    ).then((r) => r!);
  }

  Stream<StreamModelLogsReply> streamModelLogs(String instanceId) {
    return _client.stream_model_logs(
      Stream.value(StreamModelLogsRequest(instanceId: instanceId)),
    );
  }

  Future<CacheInfoReply> cacheInfo() {
    return doRpc(_client.cache_info, CacheInfoRequest()).then((r) => r!);
  }

  Future<CacheDeleteReply> cacheDelete({
    Iterable<String> ids = const [],
    bool pruneExpired = false,
  }) {
    return doRpc(
      _client.cache_delete,
      CacheDeleteRequest(ids: ids, pruneExpired: pruneExpired),
    ).then((r) => r!);
  }

  Future<void> authenticate(String passphrase) {
    return doRpc(
      _client.authenticate,
      AuthenticateRequest(passphrase: passphrase),
    );
  }
}

class CustomChannelCredentials extends ChannelCredentials {
  final List<int> certificateChain;
  final List<int> certificateKey;
  final List<int> rootCertificate;

  CustomChannelCredentials({
    String? authority,
    required List<int> certificate,
    required this.certificateKey,
    required this.rootCertificate,
    BadCertificateHandler? onBadCertificate,
  })  : certificateChain = certificate,
        super.secure(
          // Parent uses these bytes as an initial trust store; [securityContext]
          // replaces them with [rootCertificate] and installs the client identity.
          certificates: certificate,
          authority: authority,
          onBadCertificate: onBadCertificate,
        );

  @override
  SecurityContext get securityContext {
    final ctx = createSecurityContext(false);
    ctx.setTrustedCertificatesBytes(rootCertificate);
    ctx.useCertificateChainBytes(certificateChain);
    ctx.usePrivateKeyBytes(certificateKey);
    return ctx;
  }
}

/// Accept Multipass daemon certs over a Unix socket.
///
/// Stock Multipass serves `CN=localhost` without SANs. Dart/BoringSSL then fails
/// with `CERTIFICATE_VERIFY_FAILED: application verification failure` even when
/// the chain is anchored to the pinned Multipass root CA. gRPC only invokes this
/// after the built-in check fails; we still require a localhost identity.
bool allowMultipassDaemonCertificate(X509Certificate certificate, String host) {
  final hostOk = host.isEmpty || host == 'localhost';
  final subject = certificate.subject;
  final localhostIdentity = subject.contains('CN=localhost');
  return hostOk && localhostIdentity;
}

extension<T> on Stream<T> {
  Future<T?> get lastOrNull {
    final completer = Completer<T?>.sync();
    T? result;
    listen(
      (event) => result = event,
      onError: completer.completeError,
      onDone: () => completer.complete(result),
      cancelOnError: true,
    );
    return completer.future;
  }
}
