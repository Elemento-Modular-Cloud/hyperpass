# hyperpass-api

REST sidecar that translates an external-standard HTTP API to `hyperpassd` over
the existing mTLS gRPC control plane.

## Build

Enabled by default (`HYPERPASS_ENABLE_API=ON`). Disable with:

```bash
cmake -DHYPERPASS_ENABLE_API=OFF ...
```

Binary: `build/bin/hyperpass-api`

## Run (local dev)

With a dev daemon from `scripts/run-dev-daemon.sh`:

```bash
export HYPERPASS_SERVER_ADDRESS=unix:/tmp/hyperpass.socket
./scripts/run-dev-api.sh
```

Or manually:

```bash
export HYPERPASS_SERVER_ADDRESS=unix:/tmp/hyperpass.socket
./build/bin/hyperpass-api --insecure-no-auth --listen 127.0.0.1:51052
```

## Auth

By default a Bearer token is required:

```bash
./build/bin/hyperpass-api --api-token secret
curl -H "Authorization: Bearer secret" http://127.0.0.1:51052/v1/instances
```

`--insecure-no-auth` skips REST auth (local development only). The sidecar still
uses the same client certificates as the CLI when talking to `hyperpassd`.

## Endpoints (scaffold)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/healthz` | no | Liveness |
| GET | `/readyz` | no | Daemon gRPC reachable (`hyperpass` + `multipass` status) |
| GET | `/v1/instances` | yes | Merged Hyperpass + Multipass list (`source` on each item) |
| GET | `/v1/operations/{id}` | yes | Long-running operation status |

Filter instances with `?source=hyperpass` or `?source=multipass`.

Disable Multipass discovery with `--no-multipass`, or override the address with
`--multipass-address` / `HYPERPASS_MULTIPASS_ADDRESS` (same env as the GUI).

OpenAPI placeholder: [`openapi/hyperpass-external.yaml`](openapi/hyperpass-external.yaml)
