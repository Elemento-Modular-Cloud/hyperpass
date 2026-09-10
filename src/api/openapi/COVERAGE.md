# External API coverage gaps

AtomOS VM surface temporarily on matcher port **7777** (Service/Meson canonical
**7781**) — see Bruno `AtomOS/service/`. All endpoints share that listen address.

## Status

| Area | Status |
|------|--------|
| Bearer auth (Bruno) | Required on all Service paths (`/`, `/version`, `/api/v1.0/*`); probes `/healthz` `/readyz` and fingerprint paths exempt |
| HTTPS + AtomOS TLS fingerprint | HTTPS by default (opt out with `--http`); Electros peer-TLS `:7777`; `GET /api/v1/authenticate/cert?host=` dials remote `:7777`/`:7772`; `/fingerprint` returns local leaf; `/ca.crt` returns the CA PEM |
| `GET /` ping | Implemented (auth required) |
| `GET /version` | Implemented (auth required) |
| `GET /api/v1.0/canallocate` | Implemented — remaining ResourcePool RAM in MiB; POST body `req.mem.capacity` / `memory_mib` / `ram` can make `canallocate` false |
| `POST /api/v1.0/canallocate/multiple` | Remaining pool RAM; `canallocate` false when none left |
| `POST /api/v1.0/register` | Implemented → gRPC `launch` + registry; returns matcher `uniqueID`/`req_json`/`xml` plus Service `vm_uid` |
| `POST /api/v1.0/create_machine` | Alias of `register` (Meson name) |
| `GET /api/v1.0/running` | Implemented → `{"vms":[{uniqueID,req_json,xml,…}]}` (Electros/matcher) |
| `GET /api/v1.0/get_machine` | Alias of `running` (Meson name) |
| `DELETE /api/v1.0/unregister` | Implemented → `delet` (+ purge) |
| `DELETE /api/v1.0/delete_machine` | Alias of `unregister` (Meson name) |
| `POST /api/v1.0/start\|stop\|reboot` | Implemented |
| `GET /api/v1.0/images/find` | Implemented → `find` |
| VM registry (`vm_uid`) | JSON file under `…/elp-api/vm_registry.json` |
| Multipass merge (`/v1/instances`) | Extra helper (not Meson) |
| `Async: true` non-blocking register | Not implemented (always waits for launch) |
| `atomos-iso` backend | Not implemented (`backend` always `elp`) |

## Notes

- Prefer adding missing capabilities as gRPC RPCs on `elpd` first, then mapping them here.
- `req.cpu` SMT/overprovision/PCI fields are accepted for Meson parity but ignored by Electros LaunchPad.
- Revert default listen to `127.0.0.1:7781` when dropping the temporary matcher-port mapping.
