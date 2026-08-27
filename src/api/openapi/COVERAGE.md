# External API coverage gaps

AtomOS Service (Meson-compatible) surface on port 7781 — see Bruno `AtomOS/service/`.

## Status

| Area | Status |
|------|--------|
| `GET /` ping | Implemented |
| `GET /version` | Implemented |
| `POST /api/v1.0/register` | Implemented → gRPC `launch` + registry |
| `POST /api/v1.0/create_machine` | Alias of `register` (Meson name) |
| `GET /api/v1.0/running` | Implemented → `list` + registry filter by `client_uid` |
| `GET /api/v1.0/get_machine` | Alias of `running` (Meson name) |
| `DELETE /api/v1.0/unregister` | Implemented → `delet` (+ purge) |
| `DELETE /api/v1.0/delete_machine` | Alias of `unregister` (Meson name) |
| `POST /api/v1.0/start\|stop\|reboot` | Implemented |
| `GET /api/v1.0/images/find` | Implemented → `find` |
| VM registry (`vm_uid`) | JSON file under `…/hyperpass-api/vm_registry.json` |
| Multipass merge (`/v1/instances`) | Extra helper (not Meson) |
| `Async: true` non-blocking register | Not implemented (always waits for launch) |
| `atomos-iso` backend | Not implemented (`backend` always `hyperpass`) |

## Notes

- Prefer adding missing capabilities as gRPC RPCs on `hyperpassd` first, then mapping them here.
- `req.cpu` SMT/overprovision/PCI fields are accepted for Meson parity but ignored by Hyperpass.
