# hyperpass-api

REST sidecar implementing the AtomOS **Service** API (Meson-compatible VM surface on
port **7781**), translating to `hyperpassd` over mTLS gRPC.

## Build

Enabled by default (`HYPERPASS_ENABLE_API=ON`). Binary: `build/bin/hyperpass-api`

## Run (local dev)

```bash
export HYPERPASS_SERVER_ADDRESS=unix:/tmp/hyperpass.socket
./scripts/run-dev-api.sh --insecure-no-auth
```

## AtomOS Service endpoints

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/` | no | Ping (503 if hyperpassd down) |
| GET | `/version` | no | Service + backend version |
| POST | `/api/v1.0/register` | yes | Launch VM (cloud-init) |
| POST | `/api/v1.0/create_machine` | yes | Meson alias of `register` |
| GET | `/api/v1.0/running` | yes | List VMs for `client_uid` (JSON body) |
| GET | `/api/v1.0/get_machine` | yes | Meson alias of `running` |
| DELETE | `/api/v1.0/unregister` | yes | Delete (+ optional `purge`) |
| DELETE | `/api/v1.0/delete_machine` | yes | Meson alias of `unregister` |
| POST | `/api/v1.0/start` | yes | Start |
| POST | `/api/v1.0/stop` | yes | Stop |
| POST | `/api/v1.0/reboot` | yes | Restart |
| GET | `/api/v1.0/images/find` | yes | Image catalog helper |

Extra (non-Meson) helpers: `/healthz`, `/readyz`, `/v1/instances` (merged Hyperpass+Multipass).

## Auth

```bash
./build/bin/hyperpass-api --api-token secret
curl -H "Authorization: Bearer secret" \
  -H "Content-Type: application/json" \
  -d '{"client_uid":"demo"}' \
  http://127.0.0.1:7781/api/v1.0/running
```

OpenAPI: [`openapi/hyperpass-external.yaml`](openapi/hyperpass-external.yaml)  
Bruno reference: AtomOS `service/` collection (port 7781).
