# Local development alongside an installed Multipass

Use this when you already have the official Multipass package running (LaunchDaemon / snap / Windows service) and want to exercise **this tree** without replacing it.

## Build

```bash
# macOS
./scripts/build-macos.sh

# Linux
./scripts/build-linux.sh

# Windows (from a VS developer shell, or pass -EnterVsDevShell)
.\scripts\build-windows.ps1
```

See [`scripts/README.md`](./scripts/README.md) and `BUILD.*.md` for options and dependencies.

## Unit tests (no daemon required)

```bash
./scripts/build-macos.sh --gtest-filter 'CustomImageHost*:*Pollinate*'
# or after a configure:
./build/bin/multipass_cpp_tests --gtest_filter='CustomImageHost*:*Pollinate*'
```

## Side-by-side daemon (recommended)

Keep the system Multipass on its default socket. Run a second `multipassd` from your build with a **different socket**, **storage**, and (for catalog work) **distributions URL**.

### Terminal 1 — fork daemon

```bash
REPO=/Users/gabrielegaetanofronze/gitstuff/hyperpass   # adjust to your clone
mkdir -p /tmp/hyperpass-data

export MULTIPASS_STORAGE=/tmp/hyperpass-data
export MULTIPASS_DISTRIBUTIONS_URL="$REPO/data/distributions/distribution-info.json"

sudo -E "$REPO/build/bin/multipassd" \
  --logger stderr \
  --verbosity debug \
  --address unix:/tmp/hyperpass_multipass.socket
```

Leave this running. Stock Multipass continues to use `/var/run/multipass_socket` (macOS) or the platform default.

`sudo -E` preserves the environment variables. Without `-E`, set them on the sudo command line.

### Terminal 2 — fork client

```bash
REPO=/Users/gabrielegaetanofronze/gitstuff/hyperpass
export MULTIPASS_SERVER_ADDRESS=unix:/tmp/hyperpass_multipass.socket
export PATH="$REPO/build/bin:$PATH"

multipass version
multipass find          # expect debian, fedora, almalinux, rocky (and Ubuntu remotes)
multipass launch almalinux -n alma-test
multipass shell alma-test
```

Use **`build/bin/multipass`**, not the system binary, unless `MULTIPASS_SERVER_ADDRESS` is set so both sides agree on the socket.

First connection to a new daemon may require `multipass authenticate`.

### Stop

Ctrl-C in the daemon terminal. Do **not** unload `com.canonical.multipassd` unless you intend to replace the installed service.

### Recover stock CLI after local testing (macOS)

On macOS, even a side-by-side daemon still writes the **shared** gRPC root CA to `/usr/local/etc/multipassd/multipass_root_cert.pem`. That can leave the installed CLI unable to talk to the stock daemon (`certificate verify failed`, daemon version line missing).

Restore the system install with:

```bash
./scripts/recover-macos-system-multipass.sh
```

## Why separate storage and socket?

| Variable / flag | Purpose |
|-----------------|--------|
| `--address unix:…` / `MULTIPASS_SERVER_ADDRESS` | Avoid colliding with the installed daemon’s socket |
| `MULTIPASS_STORAGE` | Keep images/instances out of the official install’s data |
| `MULTIPASS_DISTRIBUTIONS_URL` | Point third-party catalog at this repo’s `distribution-info.json` (local path, `file://`, or `https://`) |

Without these, a source-built daemon would fight the stock one for the default socket and/or share its data directory.

## Do not (unless intentional)

- Point the installed LaunchDaemon/snap service at your local JSON just to “try the fork” — that changes the system install.
- Run two daemons on the same `--address` or the same `MULTIPASS_STORAGE`.
- On macOS, assume a separate `--address` / `MULTIPASS_STORAGE` fully isolates TLS: the root CA path is still global (see recovery script above).

## Related docs

- Third-party catalog override: [`docs/explanation/image.md`](./docs/explanation/image.md)
- macOS catalog note: [`BUILD.macOS.md`](./BUILD.macOS.md) (Local third-party catalog)
- CLI tests against a build tree: [`tests/cli/README.md`](./tests/cli/README.md) (`--daemon-controller=standalone --bin-dir=build/bin`)
