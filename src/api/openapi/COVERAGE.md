# External API coverage gaps

This document tracks how Hyperpass daemon capabilities map to the eventual
external REST standard. Update when the API reference arrives.

## Status

| Area | Status |
|------|--------|
| Health / readiness | Implemented (`/healthz`, `/readyz`) |
| Auth (Bearer token) | Implemented |
| Instance list | Merged Hyperpass + Multipass (`GET /v1/instances`, `source` field, `?source=` filter) |
| Multipass discovery | Same socket/cert layout as the GUI (`multipass_discovery`) |
| Long-running ops tracker | Interface + `GET /v1/operations/{id}` |
| Full external resource map | **Blocked** on API reference |

## Hyperpass gRPC capabilities without REST mapping yet

From `src/rpc/multipass.proto` `service Rpc` (non-exhaustive):

- create / launch / clone / delete / purge / recover
- start / stop / suspend / restart
- info / find / networks
- mount / umount
- snapshot / restore
- get / set / keys
- authenticate
- zones / enable_zones / disable_zones / zones_state
- cache_info / cache_delete
- wait_ready / version / daemon_info (used internally by readyz)
- shell / exec / transfer (streaming / interactive — may not belong in REST)

## External standard resources without Hyperpass equivalent

_To be filled when the API reference is available._

## Notes

- Prefer adding missing capabilities as gRPC RPCs on `hyperpassd` first, then
  mapping them in this sidecar — do not reimplement VM logic here.
- Streaming progress (launch, etc.) should use the `OperationTracker` and either
  `202 Accepted` + poll, or SSE, per the external standard.
