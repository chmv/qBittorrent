# Build qBittorrent as a fast development build with dynamic Qt (from aqt).
# Result: build\qbittorrent.exe, which needs the Qt6*.dll on PATH to run
# (this script puts them there; on another machine add <Qt>\bin to PATH).
#
# Fast to (re)build -- Qt is prebuilt, only qBittorrent compiles. Dependencies
# (libtorrent/boost/openssl/zlib) come from the vcpkg binary cache.
#
# Machine-specific paths below -- adjust if Visual Studio, Qt, or the repo move.

$ErrorActionPreference = 'Stop'

$vsRoot = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise'
$qtBin  = 'C:\Projects3\Qt\6.10.3\msvc2022_64\bin'
$repo   = 'C:\Projects\qBittorrent'

# 1. Enter the MSVC developer environment (cl/link + INCLUDE/LIB).
& "$vsRoot\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation

# 2. PATH: Qt bin (dynamic Qt DLLs -- needed to run the result) + VS-bundled CMake + Ninja.
$env:PATH = "$qtBin;" +
            "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;" +
            "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;$env:PATH"

# 3. Configure + build.
Set-Location $repo
cmake --preset win-msvc
cmake --build build

Write-Host "`nDone -> $repo\build\qbittorrent.exe  (needs Qt bin on PATH to run)" -ForegroundColor Green
