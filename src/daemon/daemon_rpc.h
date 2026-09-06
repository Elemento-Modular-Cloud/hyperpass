/*
 * Copyright (C) Canonical, Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#pragma once

#include <multipass/cert_provider.h>
#include <multipass/cert_store.h>
#include <multipass/disabled_copy_move.h>
#include <multipass/logging/multiplexing_logger.h>
#include <multipass/rpc/multipass.grpc.pb.h>

#include <grpcpp/grpcpp.h>

#include <QObject>

#include <future>
#include <memory>

namespace multipass
{

struct DaemonRpcContext;

using CreateRequest = LaunchRequest;
using CreateReply = LaunchReply;
using CreateError = LaunchError;
using CreateProgress = LaunchProgress;

// Skip running moc on this enum class since it fails parsing it
#ifndef Q_MOC_RUN
enum class ServerSocketType
{
    tcp,
    unix
};
#endif

struct DaemonConfig;
class DaemonRpc : public QObject, public multipass::Rpc::Service, private DisabledCopyMove
{
    Q_OBJECT
public:
    DaemonRpc(const std::string& server_address,
              const CertProvider& cert_provider,
              CertStore* client_cert_store,
              std::shared_ptr<logging::MultiplexingLogger> logger);

    void shutdown_and_wait();

signals:
    void on_create(const CreateRequest* request,
                   grpc::ServerReaderWriter<CreateReply, CreateRequest>* server,
                   DaemonRpcContext* context);
    void on_launch(const LaunchRequest* request,
                   grpc::ServerReaderWriter<LaunchReply, LaunchRequest>* server,
                   DaemonRpcContext* context);
    void on_purge(const PurgeRequest* request,
                  grpc::ServerReaderWriter<PurgeReply, PurgeRequest>* server,
                  DaemonRpcContext* context);
    void on_find(const FindRequest* request,
                 grpc::ServerReaderWriter<FindReply, FindRequest>* server,
                 DaemonRpcContext* context);
    void on_info(const InfoRequest* request,
                 grpc::ServerReaderWriter<InfoReply, InfoRequest>* server,
                 DaemonRpcContext* context);
    void on_list(const ListRequest* request,
                 grpc::ServerReaderWriter<ListReply, ListRequest>* server,
                 DaemonRpcContext* context);
    void on_clone(const CloneRequest* request,
                  grpc::ServerReaderWriter<CloneReply, CloneRequest>* server,
                  DaemonRpcContext* context);
    void on_networks(const NetworksRequest* request,
                     grpc::ServerReaderWriter<NetworksReply, NetworksRequest>* server,
                     DaemonRpcContext* context);
    void on_mount(const MountRequest* request,
                  grpc::ServerReaderWriter<MountReply, MountRequest>* server,
                  DaemonRpcContext* context);
    void on_recover(const RecoverRequest* request,
                    grpc::ServerReaderWriter<RecoverReply, RecoverRequest>* server,
                    DaemonRpcContext* context);
    void on_ssh_info(const SSHInfoRequest* request,
                     grpc::ServerReaderWriter<SSHInfoReply, SSHInfoRequest>* server,
                     DaemonRpcContext* context);
    void on_start(const StartRequest* request,
                  grpc::ServerReaderWriter<StartReply, StartRequest>* server,
                  DaemonRpcContext* context);
    void on_stop(const StopRequest* request,
                 grpc::ServerReaderWriter<StopReply, StopRequest>* server,
                 DaemonRpcContext* context);
    void on_suspend(const SuspendRequest* request,
                    grpc::ServerReaderWriter<SuspendReply, SuspendRequest>* server,
                    DaemonRpcContext* context);
    void on_restart(const RestartRequest* request,
                    grpc::ServerReaderWriter<RestartReply, RestartRequest>* server,
                    DaemonRpcContext* context);
    void on_delete(const DeleteRequest* request,
                   grpc::ServerReaderWriter<DeleteReply, DeleteRequest>* server,
                   DaemonRpcContext* context);
    void on_umount(const UmountRequest* request,
                   grpc::ServerReaderWriter<UmountReply, UmountRequest>* server,
                   DaemonRpcContext* context);
    void on_version(const VersionRequest* request,
                    grpc::ServerReaderWriter<VersionReply, VersionRequest>* server,
                    DaemonRpcContext* context);
    void on_get(const GetRequest* request,
                grpc::ServerReaderWriter<GetReply, GetRequest>* server,
                DaemonRpcContext* context);
    void on_set(const SetRequest* request,
                grpc::ServerReaderWriter<SetReply, SetRequest>* server,
                DaemonRpcContext* context);
    void on_keys(const KeysRequest* request,
                 grpc::ServerReaderWriter<KeysReply, KeysRequest>* server,
                 DaemonRpcContext* context);
    void on_authenticate(const AuthenticateRequest* request,
                         grpc::ServerReaderWriter<AuthenticateReply, AuthenticateRequest>* server,
                         DaemonRpcContext* context);
    void on_snapshot(const SnapshotRequest* request,
                     grpc::ServerReaderWriter<SnapshotReply, SnapshotRequest>* server,
                     DaemonRpcContext* context);
    void on_restore(const RestoreRequest* request,
                    grpc::ServerReaderWriter<RestoreReply, RestoreRequest>* server,
                    DaemonRpcContext* context);
    void on_daemon_info(const DaemonInfoRequest* request,
                        grpc::ServerReaderWriter<DaemonInfoReply, DaemonInfoRequest>* server,
                        DaemonRpcContext* context);
    void on_cache_info(const CacheInfoRequest* request,
                       grpc::ServerReaderWriter<CacheInfoReply, CacheInfoRequest>* server,
                       DaemonRpcContext* context);
    void on_cache_delete(const CacheDeleteRequest* request,
                         grpc::ServerReaderWriter<CacheDeleteReply, CacheDeleteRequest>* server,
                         DaemonRpcContext* context);
    void on_wait_ready(const WaitReadyRequest* request,
                       grpc::ServerReaderWriter<WaitReadyReply, WaitReadyRequest>* server,
                       DaemonRpcContext* context);
    void on_zones(const ZonesRequest* request,
                  grpc::ServerReaderWriter<ZonesReply, ZonesRequest>* server,
                  DaemonRpcContext* context);
    void on_zones_state(const ZonesStateRequest* request,
                        grpc::ServerReaderWriter<ZonesStateReply, ZonesStateRequest>* server,
                        DaemonRpcContext* context);
    void on_find_models(const FindModelsRequest* request,
                        grpc::ServerReaderWriter<FindModelsReply, FindModelsRequest>* server,
                        DaemonRpcContext* context);
    void on_pull_model(const PullModelRequest* request,
                       grpc::ServerReaderWriter<PullModelReply, PullModelRequest>* server,
                       DaemonRpcContext* context);
    void on_load_model(const LoadModelRequest* request,
                       grpc::ServerReaderWriter<LoadModelReply, LoadModelRequest>* server,
                       DaemonRpcContext* context);
    void on_unload_model(const UnloadModelRequest* request,
                         grpc::ServerReaderWriter<UnloadModelReply, UnloadModelRequest>* server,
                         DaemonRpcContext* context);
    void on_list_models(const ListModelsRequest* request,
                        grpc::ServerReaderWriter<ListModelsReply, ListModelsRequest>* server,
                        DaemonRpcContext* context);
    void on_list_llm_backends(
        const ListLlmBackendsRequest* request,
        grpc::ServerReaderWriter<ListLlmBackendsReply, ListLlmBackendsRequest>* server,
        DaemonRpcContext* context);
    void on_install_llm_backend(
        const InstallLlmBackendRequest* request,
        grpc::ServerReaderWriter<InstallLlmBackendReply, InstallLlmBackendRequest>* server,
        DaemonRpcContext* context);
    void on_create_api_key(const CreateApiKeyRequest* request,
                           grpc::ServerReaderWriter<CreateApiKeyReply, CreateApiKeyRequest>* server,
                           DaemonRpcContext* context);
    void on_list_api_keys(const ListApiKeysRequest* request,
                          grpc::ServerReaderWriter<ListApiKeysReply, ListApiKeysRequest>* server,
                          DaemonRpcContext* context);
    void on_revoke_api_key(const RevokeApiKeyRequest* request,
                           grpc::ServerReaderWriter<RevokeApiKeyReply, RevokeApiKeyRequest>* server,
                           DaemonRpcContext* context);
    void on_verify_api_key(const VerifyApiKeyRequest* request,
                           grpc::ServerReaderWriter<VerifyApiKeyReply, VerifyApiKeyRequest>* server,
                           DaemonRpcContext* context);
    void on_touch_model(const TouchModelRequest* request,
                        grpc::ServerReaderWriter<TouchModelReply, TouchModelRequest>* server,
                        DaemonRpcContext* context);
    void on_delete_model(const DeleteModelRequest* request,
                         grpc::ServerReaderWriter<DeleteModelReply, DeleteModelRequest>* server,
                         DaemonRpcContext* context);
    void on_stream_model_logs(
        const StreamModelLogsRequest* request,
        grpc::ServerReaderWriter<StreamModelLogsReply, StreamModelLogsRequest>* server,
        DaemonRpcContext* context);

private:
    template <typename T, typename U, typename OperationSignal>
    grpc::Status
    verify_client_and_dispatch_operation(OperationSignal signal,
                                         const std::string& client_cert,
                                         grpc::ServerReaderWriterInterface<T, U>* server);

    const std::string server_address;
    const std::unique_ptr<grpc::Server> server;
    const ServerSocketType server_socket_type;
    CertStore* client_cert_store;
    std::shared_ptr<logging::MultiplexingLogger> logger;

protected:
    grpc::Status create(grpc::ServerContext* context,
                        grpc::ServerReaderWriter<CreateReply, CreateRequest>* server) override;
    grpc::Status launch(grpc::ServerContext* context,
                        grpc::ServerReaderWriter<LaunchReply, LaunchRequest>* server) override;
    grpc::Status purge(grpc::ServerContext* context,
                       grpc::ServerReaderWriter<PurgeReply, PurgeRequest>* server) override;
    grpc::Status find(grpc::ServerContext* context,
                      grpc::ServerReaderWriter<FindReply, FindRequest>* server) override;
    grpc::Status info(grpc::ServerContext* context,
                      grpc::ServerReaderWriter<InfoReply, InfoRequest>* server) override;
    grpc::Status list(grpc::ServerContext* context,
                      grpc::ServerReaderWriter<ListReply, ListRequest>* server) override;
    grpc::Status clone(grpc::ServerContext* context,
                       grpc::ServerReaderWriter<CloneReply, CloneRequest>* server) override;
    grpc::Status networks(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<NetworksReply, NetworksRequest>* server) override;
    grpc::Status mount(grpc::ServerContext* context,
                       grpc::ServerReaderWriter<MountReply, MountRequest>* server) override;
    grpc::Status recover(grpc::ServerContext* context,
                         grpc::ServerReaderWriter<RecoverReply, RecoverRequest>* server) override;
    grpc::Status ssh_info(grpc::ServerContext* context,
                          grpc::ServerReaderWriter<SSHInfoReply, SSHInfoRequest>* server) override;
    grpc::Status start(grpc::ServerContext* context,
                       grpc::ServerReaderWriter<StartReply, StartRequest>* server) override;
    grpc::Status stop(grpc::ServerContext* context,
                      grpc::ServerReaderWriter<StopReply, StopRequest>* server) override;
    grpc::Status suspend(grpc::ServerContext* context,
                         grpc::ServerReaderWriter<SuspendReply, SuspendRequest>* server) override;
    grpc::Status restart(grpc::ServerContext* context,
                         grpc::ServerReaderWriter<RestartReply, RestartRequest>* server) override;
    grpc::Status delet(grpc::ServerContext* context,
                       grpc::ServerReaderWriter<DeleteReply, DeleteRequest>* server) override;
    grpc::Status umount(grpc::ServerContext* context,
                        grpc::ServerReaderWriter<UmountReply, UmountRequest>* server) override;
    grpc::Status version(grpc::ServerContext* context,
                         grpc::ServerReaderWriter<VersionReply, VersionRequest>* server) override;
    grpc::Status ping(grpc::ServerContext* context,
                      const PingRequest* request,
                      PingReply* reply) override;
    grpc::Status get(grpc::ServerContext* context,
                     grpc::ServerReaderWriter<GetReply, GetRequest>* server) override;
    grpc::Status set(grpc::ServerContext* context,
                     grpc::ServerReaderWriter<SetReply, SetRequest>* server) override;
    grpc::Status keys(grpc::ServerContext* context,
                      grpc::ServerReaderWriter<KeysReply, KeysRequest>* server) override;
    grpc::Status authenticate(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<AuthenticateReply, AuthenticateRequest>* server) override;
    grpc::Status snapshot(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<SnapshotReply, SnapshotRequest>* server) override;
    grpc::Status restore(grpc::ServerContext* context,
                         grpc::ServerReaderWriter<RestoreReply, RestoreRequest>* server) override;
    grpc::Status daemon_info(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<DaemonInfoReply, DaemonInfoRequest>* server) override;
    grpc::Status cache_info(grpc::ServerContext* context,
                            grpc::ServerReaderWriter<CacheInfoReply, CacheInfoRequest>* server)
        override;
    grpc::Status cache_delete(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<CacheDeleteReply, CacheDeleteRequest>* server) override;
    grpc::Status wait_ready(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<WaitReadyReply, WaitReadyRequest>* server) override;
    grpc::Status zones(grpc::ServerContext* context,
                       grpc::ServerReaderWriter<ZonesReply, ZonesRequest>* server) override;
    grpc::Status zones_state(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<ZonesStateReply, ZonesStateRequest>* server) override;
    grpc::Status find_models(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<FindModelsReply, FindModelsRequest>* server) override;
    grpc::Status pull_model(grpc::ServerContext* context,
                            grpc::ServerReaderWriter<PullModelReply, PullModelRequest>* server)
        override;
    grpc::Status load_model(grpc::ServerContext* context,
                            grpc::ServerReaderWriter<LoadModelReply, LoadModelRequest>* server)
        override;
    grpc::Status unload_model(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<UnloadModelReply, UnloadModelRequest>* server) override;
    grpc::Status list_models(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<ListModelsReply, ListModelsRequest>* server) override;
    grpc::Status list_llm_backends(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<ListLlmBackendsReply, ListLlmBackendsRequest>* server) override;
    grpc::Status install_llm_backend(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<InstallLlmBackendReply, InstallLlmBackendRequest>* server) override;
    grpc::Status create_api_key(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<CreateApiKeyReply, CreateApiKeyRequest>* server) override;
    grpc::Status list_api_keys(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<ListApiKeysReply, ListApiKeysRequest>* server) override;
    grpc::Status revoke_api_key(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<RevokeApiKeyReply, RevokeApiKeyRequest>* server) override;
    grpc::Status verify_api_key(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<VerifyApiKeyReply, VerifyApiKeyRequest>* server) override;
    grpc::Status touch_model(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<TouchModelReply, TouchModelRequest>* server) override;
    grpc::Status delete_model(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<DeleteModelReply, DeleteModelRequest>* server) override;
    grpc::Status stream_model_logs(
        grpc::ServerContext* context,
        grpc::ServerReaderWriter<StreamModelLogsReply, StreamModelLogsRequest>* server) override;
};
} // namespace multipass
