# Local development alongside an installed Multipass

Use this when you already have the official Multipass package running (LaunchDaemon / snap / Windows service) and want to exercise **Hyperpass from this tree** without replacing it.

Hyperpass defaults already diverge from Multipass (binaries, sockets, cert dirs, data paths, services). Dev scripts below still use a temporary socket/storage so you can run a build-tree daemon without installing Hyperpass.

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

Keep system Multipass on its default socket. Run Hyperpass `hyperpassd` from your build with a **temporary socket**, **storage**, and (for catalog work) **distributions URL**.

### Terminal 1 — dev daemon

```bash
./scripts/run-dev-daemon.sh
```

Leave this running. Stock Multipass continues to use `/var/run/multipass_socket` (macOS) or its platform default. Dev Hyperpass uses `/tmp/hyperpass.socket` by default.

The script sets `HYPERPASS_STORAGE`, `HYPERPASS_DISTRIBUTIONS_URL`, and `--address` for you. It also auto-exports `HYPERPASS_LLMFIT` and `HYPERPASS_LLAMA_SERVER` when those binaries are on your PATH (needed for Models catalog search and loading GGUF files). Override with environment variables if needed (see `./scripts/run-dev-daemon.sh --help`).

**Models / LLM:** Download succeeded but **Load** failed with `llama-server is not installed` means the daemon cannot find [llama.cpp](https://github.com/ggerganov/llama.cpp)'s server binary. Install it (e.g. `brew install llama.cpp` if available, or build from source), then restart the dev daemon:

```bash
export HYPERPASS_LLAMA_SERVER="$(command -v llama-server)"
./scripts/run-dev-daemon.sh --stop
./scripts/run-dev-daemon.sh
```

Then use **Load** again on the Downloads tab for the cached model.

### Terminal 2 — CLI or GUI

**CLI:**

```bash
export HYPERPASS_SERVER_ADDRESS=unix:/tmp/hyperpass.socket
export PATH="$PWD/build/bin:$PATH"

hyperpass version
hyperpass find          # expect debian, fedora, almalinux, rocky (and Ubuntu remotes)
hyperpass launch almalinux -n alma-test
hyperpass shell alma-test
```

**GUI:**

```bash
./scripts/run-dev-gui.sh
```

Use **`build/bin/hyperpass`**, not the system Multipass binary.

First connection to a new daemon may require `hyperpass authenticate`.

### Stop

```bash
./scripts/run-dev-daemon.sh --stop
```

Or Ctrl-C in the daemon terminal (shutdown can take a moment during startup or while VMs are running). Do **not** unload `com.canonical.multipassd` unless you intend to replace the installed Multipass service.

### Manual invocation (equivalent)

```bash
REPO="$PWD"   # repo root
mkdir -p /tmp/hyperpass-data

export HYPERPASS_STORAGE=/tmp/hyperpass-data
export HYPERPASS_DISTRIBUTIONS_URL="$REPO/data/distributions/distribution-info.json"

sudo -E "$REPO/build/bin/hyperpassd" \
  --logger stderr \
  --verbosity debug \
  --address unix:/tmp/hyperpass.socket
```

`sudo -E` preserves the environment variables. Without `-E`, set them on the sudo command line.

### Recover stock Multipass CLI (macOS, legacy)

Older Hyperpass builds that still wrote Multipass’s root CA path could break the installed Multipass CLI. Current Hyperpass uses `/usr/local/etc/hyperpassd/` instead, so this should not happen.

If you still need to restore stock Multipass TLS:

```bash
./scripts/recover-macos-system-multipass.sh
```

## Why separate storage and socket for build-tree testing?

| Variable / flag | Purpose |
|-----------------|--------|
| `--address unix:…` / `HYPERPASS_SERVER_ADDRESS` | Point CLI/GUI at the build-tree daemon |
| `HYPERPASS_STORAGE` | Keep images/instances out of an installed Hyperpass data dir |
| `HYPERPASS_DISTRIBUTIONS_URL` | Point third-party catalog at this repo’s `distribution-info.json` |

A packaged Hyperpass install already uses distinct defaults from Multipass and can coexist without these overrides.

## GUI: Multipass instances alongside Hyperpass

The Hyperpass GUI can **list and manage** stock Multipass instances when Multipass is installed and its client certificates are present. New launches always go to Hyperpass.

- Discovery uses platform Multipass defaults (macOS `unix:/var/run/multipass_socket`, Linux `/run/multipass_socket` or snap common, Windows `localhost:50051`) plus Multipass root CA and `multipass-client-certificate` PEMs.
- Override the Multipass address with `HYPERPASS_MULTIPASS_ADDRESS` (same `unix:…` / `host:port` forms as Hyperpass).
- Toggle visibility under **Settings → General → Show Multipass instances** (default on).
- Multipass rows show a small **Multipass** tag; if TLS auth is required, the GUI offers an authenticate dialog.

## Launch / shell troubleshooting

### QEMU `Process crashed` on macOS

If hyperpassd logs `Process crashed` for `qemu-system-aarch64` (including on `--version` or VM start), the build-tree QEMU likely lacks the **hypervisor** entitlement. vcpkg copies an unsigned binary into `build/bin/`; macOS kills it when HVF or Hypervisor.framework is involved.

After each build, run (or rely on `./scripts/build-macos.sh`, which does this automatically):

```bash
./scripts/sign-dev-macos-binaries.sh
```

Verify:

```bash
codesign -dv --entitlements - build/bin/qemu-system-aarch64 | rg hypervisor
build/bin/qemu-system-aarch64 --version
```

Then restart the dev daemon: `./scripts/run-dev-daemon.sh --stop` and `./scripts/run-dev-daemon.sh`.

While an instance is **Starting** (boot or cloud-init in progress), do not run `hyperpass shell` or `hyperpass exec` against it. Wait until launch finishes or `hyperpass list` shows **Running**.

If the CLI stops responding, a long-running `launch`/`start` may be holding the daemon busy. Use `./scripts/run-dev-daemon.sh --stop` and restart the dev daemon, or wait for the in-flight launch to complete (default timeout is five minutes per phase).

## Do not (unless intentional)

- Point the installed Multipass LaunchDaemon/snap service at your local JSON just to “try the fork” — that changes the system Multipass install.
- Run two Hyperpass daemons on the same `--address` or the same `HYPERPASS_STORAGE`.

## Related docs

- Third-party catalog override: [`docs/explanation/image.md`](./docs/explanation/image.md)
- macOS catalog note: [`BUILD.macOS.md`](./BUILD.macOS.md) (Local third-party catalog)
- CLI tests against a build tree: [`tests/cli/README.md`](./tests/cli/README.md) (`--daemon-controller=standalone --bin-dir=build/bin`)
