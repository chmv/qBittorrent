# Build qBittorrent as a static, self-contained single .exe (like the official release).
# Result: build-static\qbittorrent.exe with no external Qt/CRT DLL dependencies.
#
# Prerequisite: a static Qt at $qtStatic. If missing, run build-qt-static.ps1 first
# (compiles Qt from source -- long, one-time). qBittorrent's own dependencies
# (libtorrent/boost/openssl/zlib) come from vcpkg (binary cache -> fast).
#
# Machine-specific paths below -- adjust if Visual Studio or the repo move.

$ErrorActionPreference = 'Stop'

$vsRoot   = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise'
$repo     = 'C:\Projects\qBittorrent'
$qtStatic = 'C:\Projects3\Qt\6.10.3-static'

if (-not (Test-Path "$qtStatic\lib\Qt6Core.lib")) {
    throw "Static Qt not found at $qtStatic. Run build-qt-static.ps1 first."
}

# 1. Enter the MSVC developer environment (cl/link + INCLUDE/LIB).
& "$vsRoot\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation

# 2. Put the VS-bundled CMake + Ninja on PATH (not there by default).
$env:PATH = "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;" +
            "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;$env:PATH"

# 3. Configure (Qt from $qtStatic; deps from the vcpkg binary cache) and build.
Set-Location $repo
cmake --preset win-msvc-static
cmake --build build-static

Write-Host "`nDone -> $repo\build-static\qbittorrent.exe  (single self-contained exe)" -ForegroundColor Green
