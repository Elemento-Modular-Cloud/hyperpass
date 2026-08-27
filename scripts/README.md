# Build scripts

Convenience wrappers around the platform build flows documented in:

- [BUILD.linux.md](../BUILD.linux.md)
- [BUILD.macOS.md](../BUILD.macOS.md)
- [BUILD.windows.md](../BUILD.windows.md)

These scripts configure, build, and optionally test or package Multipass. They do **not** install system dependencies (Homebrew, apt `mk-build-deps`, Chocolatey, Visual Studio, Flutter/CocoaPods, etc.) — set those up once per the docs above.

## macOS

```bash
./scripts/build-macos.sh
./scripts/build-macos.sh --build-type RelWithDebInfo --test
./scripts/build-macos.sh --gtest-filter 'CustomImageHost*:*Pollinate*'
./scripts/build-macos.sh --package
```

## Linux

```bash
./scripts/build-linux.sh
./scripts/build-linux.sh --build-type RelWithDebInfo --test
./scripts/build-linux.sh --gtest-filter 'CustomImageHost*:*Pollinate*'
```

On non-x86_64 hosts the script sets `VCPKG_FORCE_SYSTEM_BINARIES=1` automatically.

## Windows

From PowerShell (optionally with `-EnterVsDevShell` if you are not already in a VS developer shell):

```powershell
.\scripts\build-windows.ps1
.\scripts\build-windows.ps1 -BuildType RelWithDebInfo -Test
.\scripts\build-windows.ps1 -GTestFilter 'CustomImageHost*;*Pollinate*'
.\scripts\build-windows.ps1 -EnterVsDevShell -Package
```

## Common options

| Flag | Meaning |
|------|---------|
| `--build-dir` / `-BuildDir` | Out-of-tree build directory (default: `./build`) |
| `--build-type` / `-BuildType` | CMake build type (default: `Debug`) |
| `--jobs` / `-Jobs` | Parallel build jobs |
| `--test` / `-Test` | Run `ctest` after build |
| `--gtest-filter` / `-GTestFilter` | Run filtered `multipass_cpp_tests` |
| `--package` / `-Package` | Build the `package` target |
| `--configure-only` / `-ConfigureOnly` | Configure only |
| `--build-only` / `-BuildOnly` | Build without reconfigure |
| `--no-submodules` / `-NoSubmodules` | Skip `git submodule update` |

Pass extra CMake configure arguments after `--` (Unix) or as remaining args (Windows), or via the `CMAKE_ARGS` environment variable.

## Side-by-side with an installed Multipass

See [`LOCAL_DEV.md`](../LOCAL_DEV.md) for running a built `hyperpassd` next to system Multipass (separate socket, storage, and distributions catalog).

```bash
./scripts/run-dev-daemon.sh
./scripts/run-dev-api.sh --insecure-no-auth
```
```bash
# Terminal 1 — dev daemon (requires sudo on macOS/Linux)
./scripts/run-dev-daemon.sh

# Terminal 2 — dev GUI (or use the CLI env vars from LOCAL_DEV.md)
./scripts/run-dev-gui.sh

# Stop the dev daemon
./scripts/run-dev-daemon.sh --stop
```

On macOS, if the stock CLI later fails with `certificate verify failed` after local daemon testing, regenerate the system gRPC certs:

```bash
./scripts/recover-macos-system-multipass.sh
```
