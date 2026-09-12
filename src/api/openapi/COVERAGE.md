# External API coverage

Spot v2 VM/service surface on matcher port **7777** — see Bruno `AtomOS/spot`.
All endpoints share that listen address. Models stay on the existing control-plane
and OpenAI routes.

## Status

| Area | Status |
|------|--------|
| Bearer auth (Bruno) | Required on `/`, `/version`, `/api/v1.0/*`; probes `/healthz` `/readyz` and fingerprint paths exempt |
| HTTPS + AtomOS TLS fingerprint | HTTPS by default (opt out with `--http`); Electros peer-TLS `:7777`; `GET /api/v1/authenticate/cert?host=` dials remote `:7777`/`:7772`; `/fingerprint` returns local leaf; `/ca.crt` returns the CA PEM |
| `GET /` ping | Implemented (auth required) |
| `GET /version` | Implemented (auth required) |
| `GET/POST /api/v1.0/canallocate` | Spot spec (`mem.capacity_mb`, `cpu.slots`); `{canallocate}` |
| `POST /api/v1.0/register` | Spot spec → gRPC `launch`; `{vm_uid, vm_name, status}`; `507` if it cannot place |
| `GET /api/v1.0/running` | JSON array of public v2 objects (elp + Multipass; lazy-upsert `vm_uid`) |
| `GET /api/v1.0/credentials/{vm_uid}` | SSH from `ssh_info` on the record's source daemon; template URL for tagged services |
| `DELETE /api/v1.0/unregister` | `{vm_uid}` → delete+purge on the source daemon |
| `startup.template` | Marketplace render from `ELP_MARKETPLACE_DIR` / `ELP_MARKETPLACE_URL` |
| VM registry (`vm_uid`) | JSON file under `…/elp-api/vm_registry.json` (Spot shape + `source`; v1 rows skipped) |
| Multipass merge (`/v1/instances`) | Extra helper (not Spot); same Multipass instances also appear on `/running` |
| PCI / extra disks / public-private NICs | Accepted and echoed; not placed |
| start/stop/reboot REST | Not on Spot (gRPC/GUI only) |

## Notes

- Prefer adding missing capabilities as gRPC RPCs on `elpd` first, then mapping them here.
- Guest `service-info` token scraping (openclaw `token`) is not implemented yet.
