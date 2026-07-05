# Build qBittorrent with MSVC.
#
#   .\build.ps1          Fast development build with dynamic Qt (from aqt); builds the tests too.
#                        Result: build\qbittorrent.exe, which needs the Qt6*.dll on PATH to run
#                        (this script puts them there; on another machine add <Qt>\bin to PATH).
#   .\build.ps1 -Static  Static, self-contained single .exe (like the official release).
#                        Result: build-static\qbittorrent.exe with no external Qt/CRT DLL
#                        dependencies. Prerequisite: a static Qt at $qtStatic. If missing, run
#                        build-qt-static.ps1 first (compiles Qt from source -- long, one-time).
#
# The presets (CMakeUserPresets.json) pick Qt, the vcpkg triplet, build type and build dir.
# qBittorrent's own dependencies (libtorrent/boost/openssl/zlib) come from vcpkg. Its
# binary cache makes that fast, except after an MSVC toolset update: the ABI hash
# includes the compiler, so every port rebuilds from source and a run takes ~10 min
# instead of a few.
#
# Machine-specific paths below -- adjust if Visual Studio, Qt, or the repo move.

param(
    [switch]$Static
)

$ErrorActionPreference = 'Stop'

$vsRoot   = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise'
$qtBin    = 'C:\Projects3\Qt\6.10.3\msvc2022_64\bin'
$qtStatic = 'C:\Projects3\Qt\6.10.3-static'
$repo     = 'C:\Projects\qBittorrent'

if ($Static -and -not (Test-Path "$qtStatic\lib\Qt6Core.lib")) {
    throw "Static Qt not found at $qtStatic. Run build-qt-static.ps1 first."
}

# 1. Enter the MSVC developer environment (cl/link + INCLUDE/LIB).
#    It prints "'vswhere.exe' is not recognized" -- harmless, the shell still initializes.
& "$vsRoot\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation

# 2. PATH: the VS-bundled CMake + Ninja (not there by default); for the dynamic build
#    also Qt bin (the Qt DLLs are needed to run the result).
$env:PATH = "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;" +
            "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;$env:PATH"
if (-not $Static) {
    $env:PATH = "$qtBin;$env:PATH"
}

# 3. Configure + build.
#    $ErrorActionPreference does not apply to native commands -- check their exit codes.
$preset   = if ($Static) { 'win-msvc-static' } else { 'win-msvc' }
$buildDir = if ($Static) { 'build-static' } else { 'build' }
Set-Location $repo
cmake --preset $preset
if ($LASTEXITCODE -ne 0) { throw 'configure failed' }
cmake --build $buildDir
if ($LASTEXITCODE -ne 0) { throw 'build failed' }

$note = if ($Static) { 'single self-contained exe' } else { 'needs Qt bin on PATH to run' }
Write-Host "`nDone -> $repo\$buildDir\qbittorrent.exe  ($note)" -ForegroundColor Green
