# Local development alongside an installed Multipass

Use this when you already have the official Multipass package running (LaunchDaemon / snap / Windows service) and want to exercise **Electros LaunchPad from this tree** without replacing it.

Electros LaunchPad defaults already diverge from Multipass (binaries, sockets, cert dirs, data paths, services). Dev scripts below still use a temporary socket/storage so you can run a build-tree daemon without installing Electros LaunchPad.

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

Keep system Multipass on its default socket. Run Electros LaunchPad `elpd` from your build with a **temporary socket**, **storage**, and (for catalog work) **distributions URL**.

### Terminal 1 — dev daemon

```bash
./scripts/run-dev-daemon.sh
```

Leave this running. Stock Multipass continues to use `/var/run/multipass_socket` (macOS) or its platform default. Dev Electros LaunchPad uses `/tmp/elp.socket` by default.

The script sets `ELP_STORAGE`, `ELP_DISTRIBUTIONS_URL`, and `--address` for you. It also auto-exports `ELP_LLMFIT` and `ELP_LLAMA_SERVER` when those binaries are on your PATH. Override with environment variables if needed (see `./scripts/run-dev-daemon.sh --help`).

**Models / LLM:** The daemon can also **auto-install** pinned `llmfit` and `llama-server` into `$ELP_STORAGE/data/llm/tools/` via the GUI (**Models → Backends → Install**). Env overrides still win over managed installs and PATH.

If **Load** fails with `llama-server is not installed`, either use **Install** in the GUI, or install yourself and point the daemon at it:

```bash
export ELP_LLAMA_SERVER="$(command -v llama-server)"
./scripts/run-dev-daemon.sh --stop
./scripts/run-dev-daemon.sh
```

Then use **Load** again on the Downloads tab for the cached model.

### Terminal 2 — CLI or GUI

**CLI:**

```bash
export ELP_SERVER_ADDRESS=unix:/tmp/elp.socket
export PATH="$PWD/build/bin:$PATH"

elp version
elp find          # expect debian, fedora, almalinux, rocky (and Ubuntu remotes)
elp launch almalinux -n alma-test
elp shell alma-test
```

**GUI:**

```bash
./scripts/run-dev-gui.sh
```

The GUI reads a **clone-shaped marketplace directory** (`services/<id>/service.yaml`, …) from `ELP_MARKETPLACE_DIR` and reloads when those files change. `run-dev-gui.sh` clones [elemento-marketplace](https://github.com/Elemento-Modular-Cloud/elemento-marketplace) into `.cache/elemento-marketplace` if needed and fast-forwards that checkout when online (override with `ELP_MARKETPLACE_DIR` / `ELP_MARKETPLACE_REF`). Production will drop the same layout via CDN.

Use **`build/bin/elp`**, not the system Multipass binary.

First connection to a new daemon may require `elp authenticate`.

### Stop

```bash
./scripts/run-dev-daemon.sh --stop
```

Or Ctrl-C in the daemon terminal (shutdown can take a moment during startup or while VMs are running). Do **not** unload `com.canonical.multipassd` unless you intend to replace the installed Multipass service.

### Manual invocation (equivalent)

```bash
REPO="$PWD"   # repo root
mkdir -p /tmp/elp-data

export ELP_STORAGE=/tmp/elp-data
export ELP_DISTRIBUTIONS_URL="$REPO/data/distributions/distribution-info.json"

sudo -E "$REPO/build/bin/elpd" \
  --logger stderr \
  --verbosity debug \
  --address unix:/tmp/elp.socket
```

`sudo -E` preserves the environment variables. Without `-E`, set them on the sudo command line.

### Recover stock Multipass CLI (macOS, legacy)

Older Electros LaunchPad builds that still wrote Multipass’s root CA path could break the installed Multipass CLI. Current Electros LaunchPad uses `/usr/local/etc/elpd/` instead, so this should not happen.

If you still need to restore stock Multipass TLS:

```bash
./scripts/recover-macos-system-multipass.sh
```

## Why separate storage and socket for build-tree testing?

| Variable / flag | Purpose |
|-----------------|--------|
| `--address unix:…` / `ELP_SERVER_ADDRESS` | Point CLI/GUI at the build-tree daemon |
| `ELP_STORAGE` | Keep images/instances out of an installed Electros LaunchPad data dir |
| `ELP_DISTRIBUTIONS_URL` | Point third-party catalog at this repo’s `distribution-info.json` |

A packaged Electros LaunchPad install already uses distinct defaults from Multipass and can coexist without these overrides.

## GUI: Multipass instances alongside Electros LaunchPad

The Electros LaunchPad GUI can **list and manage** stock Multipass instances when Multipass is installed and its client certificates are present. New launches always go to Electros LaunchPad.

- Discovery uses platform Multipass defaults (macOS `unix:/var/run/multipass_socket`, Linux `/run/multipass_socket` or snap common, Windows `localhost:50051`) plus Multipass root CA and `multipass-client-certificate` PEMs.
- Override the Multipass address with `ELP_MULTIPASS_ADDRESS` (same `unix:…` / `host:port` forms as Electros LaunchPad).
- Toggle visibility under **Settings → General → Show Multipass instances** (default on).
- Multipass rows show a small **Multipass** tag; if TLS auth is required, the GUI offers an authenticate dialog.

## Launch / shell troubleshooting

### QEMU `Process crashed` on macOS

If elpd logs `Process crashed` for `qemu-system-aarch64` (including on `--version` or VM start), the build-tree QEMU likely lacks the **hypervisor** entitlement. vcpkg copies an unsigned binary into `build/bin/`; macOS kills it when HVF or Hypervisor.framework is involved.

The same `Process crashed` for `qemu-img` (even on `info` / `--version`) means the binary's code signature is **invalid**. Packaging's `fixup-qemu-and-deps.sh` runs `install_name_tool` on `build/bin/qemu-img`, which breaks the vcpkg signature; macOS then SIGKILLs the process.

After each build (and after packaging), run (or rely on `./scripts/build-macos.sh`, which does this automatically):

```bash
./scripts/sign-dev-macos-binaries.sh
```

Verify:

```bash
codesign -dv --entitlements - build/bin/qemu-system-aarch64 | rg hypervisor
build/bin/qemu-system-aarch64 --version
codesign --verify --verbose build/bin/qemu-img
build/bin/qemu-img --version
```

Then restart the dev daemon: `./scripts/run-dev-daemon.sh --stop` and `./scripts/run-dev-daemon.sh`.

While an instance is **Starting** (boot or cloud-init in progress), do not run `elp shell` or `elp exec` against it. Wait until launch finishes or `elp list` shows **Running**.

If the CLI stops responding, a long-running `launch`/`start` may be holding the daemon busy. Use `./scripts/run-dev-daemon.sh --stop` and restart the dev daemon, or wait for the in-flight launch to complete (default timeout is five minutes per phase).

## Do not (unless intentional)

- Point the installed Multipass LaunchDaemon/snap service at your local JSON just to “try the fork” — that changes the system Multipass install.
- Run two Electros LaunchPad daemons on the same `--address` or the same `ELP_STORAGE`.

## Related docs

- Third-party catalog override: [`docs/explanation/image.md`](./docs/explanation/image.md)
- macOS catalog note: [`BUILD.macOS.md`](./BUILD.macOS.md) (Local third-party catalog)
- CLI tests against a build tree: [`tests/cli/README.md`](./tests/cli/README.md) (`--daemon-controller=standalone --bin-dir=build/bin`)
