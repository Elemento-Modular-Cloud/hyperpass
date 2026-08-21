# Build Multipass on Windows (see BUILD.windows.md).
# Run from a VS developer shell (x64 Native Tools / Enter-VsDevShell), or let
# this script attempt to enter the Build Tools environment.
[CmdletBinding()]
param(
    [string]$BuildDir = "",
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string]$BuildType = "Debug",
    [int]$Jobs = 0,
    [switch]$NoSubmodules,
    [switch]$ConfigureOnly,
    [switch]$BuildOnly,
    [switch]$Test,
    [string]$GTestFilter = "",
    [switch]$Package,
    [switch]$EnterVsDevShell,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraCMakeArgs
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $BuildDir) {
    $BuildDir = Join-Path $Root "build"
}
if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount)
}
if ($GTestFilter) {
    $Test = $true
}

function Enter-MultipassVsDevShell {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found. Install Visual Studio Build Tools or run from a VS developer shell."
    }

    $vsPath = & $vswhere -products * -latest -property installationPath
    if (-not $vsPath) {
        throw "No Visual Studio installation found."
    }

    $devShell = Join-Path $vsPath "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
    Import-Module $devShell
    Enter-VsDevShell -VsInstallPath $vsPath -DevCmdArguments "-arch=x64" | Out-Null
    Write-Host "==> Entered VS Dev Shell at $vsPath"
}

if ($EnterVsDevShell -or -not $env:VCINSTALLDIR) {
    Enter-MultipassVsDevShell
}

Set-Location $Root

if (-not $NoSubmodules) {
    Write-Host "==> Updating submodules"
    git submodule update --init --recursive
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$doConfigure = -not $BuildOnly
$doBuild = -not $ConfigureOnly

if ($doConfigure) {
    Write-Host "==> Configuring ($BuildType) in $BuildDir"
    $cmakeArgs = @(
        "-S", $Root,
        "-B", $BuildDir,
        "-GNinja",
        "-DCMAKE_BUILD_TYPE=$BuildType"
    )
    if ($ExtraCMakeArgs) {
        $cmakeArgs += $ExtraCMakeArgs
    }
    if ($env:CMAKE_ARGS) {
        $cmakeArgs += ($env:CMAKE_ARGS -split '\s+' | Where-Object { $_ })
    }
    & cmake @cmakeArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($doBuild) {
    Write-Host "==> Building (jobs=$Jobs)"
    & cmake --build $BuildDir --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($Test) {
    Write-Host "==> Running tests"
    if ($GTestFilter) {
        $testBin = Join-Path $BuildDir "bin\multipass_cpp_tests.exe"
        if (-not (Test-Path $testBin)) {
            $testBin = Join-Path $BuildDir "multipass_cpp_tests.exe"
        }
        & $testBin "--gtest_filter=$GTestFilter"
    } else {
        & ctest --test-dir $BuildDir --output-on-failure
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($Package) {
    Write-Host "==> Packaging"
    & cmake --build $BuildDir --target package --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "==> Done"
