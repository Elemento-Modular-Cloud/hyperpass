# elp-api

REST sidecar implementing the **Spot v2** VM/service API on matcher port **7777**,
translating to `elpd` over mTLS gRPC. All endpoints — including fingerprint
discovery — share that listen port on localhost and the Electros LaunchPad VM
gateway (`192.168.67.1`).

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

Marketplace templates (`startup.template`, e.g. `n8n` / `n8n_v3`) need a checkout
or JSON bundle:

```bash
export ELP_MARKETPLACE_DIR=/path/to/elemento-marketplace
# or: export ELP_MARKETPLACE_URL=https://example/marketplace_services.json
```

## Spot VM endpoints (port 7777)

Aligned with Bruno `AtomOS/spot`. All Spot paths require
`Authorization: Bearer <token>` unless `--insecure-no-auth`. Optional routing
headers: `X-Target-ID`, `X-Region` (region is stored and echoed; default `local`).

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/` | yes | Ping (503 if elpd down) |
| GET | `/version` | yes | Service + backend version |
| GET | `/api/v1.0/canallocate` | yes | Dry-run placement from Spot spec (POST accepted too) |
| POST | `/api/v1.0/register` | yes | Create + boot; `{vm_uid, vm_name, status}` |
| GET | `/api/v1.0/running` | yes | JSON array of v2 instances (elp + Multipass; lazy-upsert) |
| GET | `/api/v1.0/credentials/{vm_uid}` | yes | SSH and/or template URL |
| DELETE | `/api/v1.0/unregister` | yes | Destroy; body `{vm_uid}` |

Register bootstrap: `startup.template` (marketplace recipe) wins over
`cloud_init_b64` / `startup.b64_code`. `auth` is always merged into cloud-init.
Tags such as `service:n8n` (or the template handle) set gRPC `service_id` so the
GUI Services tab lists REST-launched guests.

`GET /running` lists every instance currently on `elpd` and (when discovered) stock
Multipass. Guests launched from the GUI/CLI are lazy-upserted into
`vm_registry.json` with a stable `vm_uid`. `credentials` and `unregister` follow
that `source` so Multipass VMs are not sent to `elpd`. CPU/RAM/disk for those
adopted rows are unknown (`0`) until a REST `register` supplies a Spot spec.

PCI devices, extra data disks, and non-natted NICs are accepted and echoed but
not placed yet.

OpenAI inference (`sk-elp-` keys only; matcher token is rejected):

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/v1/models` | `Bearer sk-elp-…` | Loaded models |
| POST | `/v1/chat/completions` | `Bearer sk-elp-…` | Proxied to localhost llama-server |
| POST | `/v1/completions` | `Bearer sk-elp-…` | Proxied to localhost llama-server |
| POST | `/v1/embeddings` | `Bearer sk-elp-…` | Proxied to localhost llama-server |

Control plane (matcher Bearer): `GET /api/v1.0/models`,
`POST /api/v1.0/models/suggested|pull|load|unload`.

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
Bruno reference: AtomOS `spot/` collection.
