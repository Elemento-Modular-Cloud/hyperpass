# elp-api

REST sidecar implementing the AtomOS VM API (temporarily on matcher port **7777**;
Service/Meson canonical is 7781), translating to `elpd` over mTLS gRPC.
All endpoints — including fingerprint discovery — share that listen port on
localhost and the Electros LaunchPad VM gateway (`192.168.67.1`).

## Build

Enabled by default (`ELP_ENABLE_API=ON`). Binary: `build/bin/elp-api`

## Run (local dev)

```bash
export ELP_SERVER_ADDRESS=unix:/tmp/elp.socket
# Prefer a token (matches Bruno Bearer auth). --insecure-no-auth is local-only.
# HTTPS is on by default (Electros fingerprints the peer cert on :7777).
./scripts/run-dev-api.sh --token secret
# or: ./scripts/run-dev-api.sh --insecure-no-auth
# Plain HTTP (debug only): ./scripts/run-dev-api.sh --token secret --http
```

## AtomOS VM endpoints (port 7777, temporary)

Aligned with Bruno `AtomOS/service/` (including Meson aliases). All Service paths
require `Authorization: Bearer <token>` unless `--insecure-no-auth`.

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/` | yes | Ping (503 if elpd down) |
| GET | `/version` | yes | Service + backend version |
| GET | `/api/v1.0/canallocate` | yes | Remaining ResourcePool RAM (MiB); body can request `req.mem.capacity` |
| POST | `/api/v1.0/register` | yes | Launch VM (returns `uniqueID` + `vm_uid`) |
| POST | `/api/v1.0/create_machine` | yes | Meson alias of `register` |
| GET | `/api/v1.0/running` | yes | List VMs: `{"vms":[{uniqueID,req_json,xml,…}]}` |
| GET | `/api/v1.0/get_machine` | yes | Meson alias of `running` |
| DELETE | `/api/v1.0/unregister` | yes | Delete (+ optional `purge`) |
| DELETE | `/api/v1.0/delete_machine` | yes | Meson alias of `unregister` |
| POST | `/api/v1.0/start` | yes | Start |
| POST | `/api/v1.0/stop` | yes | Stop |
| POST | `/api/v1.0/reboot` | yes | Restart |
| GET | `/api/v1.0/images/find` | yes | Image catalog helper |
| GET | `/api/v1.0/models` | yes | Loaded models (control plane; matcher Bearer) |
| POST | `/api/v1.0/models/suggested\|pull\|load\|unload` | yes | llmfit suggestions and vault load |

OpenAI inference (`sk-elp-` keys only; matcher token is rejected):

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/v1/models` | `Bearer sk-elp-…` | Loaded models |
| POST | `/v1/chat/completions` | `Bearer sk-elp-…` | Proxied to localhost llama-server |
| POST | `/v1/completions` | `Bearer sk-elp-…` | Proxied to localhost llama-server |
| POST | `/v1/embeddings` | `Bearer sk-elp-…` | Proxied to localhost llama-server |

Extras (no auth): `/healthz`, `/readyz`, `/fingerprint`, `/ca.crt`, `/api/v1/authenticate/cert`.  
Extra (matcher auth): `/v1/instances`.

## HTTPS + fingerprint

Electros does **not** call an HTTP fingerprint route on the remote matcher. It opens a
TLS connection to `host:7777` (fallback `:7772`) and SHA-256s the peer cert DER.

Electros LaunchPad exposes the same probe as Electros' local auth client, on the VM API port:

```bash
# Against a real AtomOS matcher (Electros-compatible):
curl -k "https://127.0.0.1:7777/api/v1/authenticate/cert?host=172.16.25.197"
# {"fingerprint":"46:59:…","validated":false}

# Local cert convenience:
./scripts/run-dev-api.sh --token secret
curl -k https://127.0.0.1:7777/fingerprint
curl -k https://127.0.0.1:7777/ca.crt
```

Auto-generated HTTPS uses a local CA plus a `serverAuth` leaf with SAN
`DNS:localhost`, `IP:127.0.0.1`, and `IP:192.168.67.1` (plus any extra `--listen`
hosts), stored as `ca.pem` / `server.pem` under `…/elp-api/https/`. `/ca.crt`
returns the CA PEM so LaunchPad VMs can trust `https://192.168.67.1:7777`.
The Electros fingerprint is still SHA-256 of the **leaf**.

HTTPS is the default so Electros can dial this host's `:7777` TLS the same way it
does for AtomOS matcher.

Options:

| Flag / env | Meaning |
|------------|---------|
| `--listen` / `ELP_API_LISTEN` | All endpoints (default `127.0.0.1,192.168.67.1:7777`) |
| `--http` | Opt out of TLS (debug only; breaks Electros fingerprinting) |
| `--cert` / `ELP_API_CERT` | Existing certificate PEM (HTTPS is default) |
| `--key` / `ELP_API_KEY` | Matching private key PEM |

Providing `--cert`/`--key` uses those PEMs (`/ca.crt` then returns the leaf).
Otherwise Electros LaunchPad prefers shared `/etc/elemento/certs/atomos.{crt,key}`
when present, else auto-generates a CA + server pair under `…/elp-api/https/`.
On AtomOS hosts, prefer the shared `atomos.*` pair so one Electros TOFU pin
covers matcher and Electros LaunchPad.

## Auth

Matches AtomOS Bruno collection headers (`Authorization: Bearer {{auth_token}}`).

```bash
./build/bin/elp-api --api-token secret
curl -k -H "Authorization: Bearer secret" https://127.0.0.1:7777/
```

OpenAI `/v1/*` does **not** accept this matcher token. Create a dedicated key with
`elp llm key create` and pass `Authorization: Bearer sk-elp-…`.

## Logging

Default (`info`): one line per HTTP request (`GET /path -> 200`).

```bash
./scripts/run-dev-api.sh --token secret --verbosity debug
```

With `debug`/`trace`: pre-routing request details plus service-flow logs (register, canallocate, …). Auth failures log at `warning`.

OpenAPI: [`openapi/elp-external.yaml`](openapi/elp-external.yaml)  
Bruno reference: AtomOS `service/` collection (temporarily on port 7777).
