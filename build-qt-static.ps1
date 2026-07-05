# Build a STATIC Qt 6.10.3 from source (qtbase + qtsvg + qttools) -- the prerequisite
# for a self-contained qBittorrent build. Reproduces C:\Projects3\Qt\6.10.3-static.
#
# Run once (or after deleting the Qt folder). LONG: downloads Qt source and compiles
# Qt from scratch -- hours, ~15 GB of build scratch. The only lasting output is the
# install prefix ($qtStatic); the Src and build dirs under $qtRoot are disposable.
#
# This is the same approach the official qBittorrent release uses (static Qt built
# from source with bundled 3rd-party libs), NOT vcpkg -- which avoids the transitive
# CMake-target issues vcpkg's static Qt hits.
#
# Machine-specific paths below -- adjust if Visual Studio / Python / target move.

$ErrorActionPreference = 'Stop'

$vsRoot   = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise'
$python   = 'C:\Program Files\Python314'
$qtVer    = '6.10.3'
$qtRoot   = 'C:\Projects3\Qt'              # aqt output; source + build trees live here
$src      = "$qtRoot\$qtVer\Src"
$buildDir = "$qtRoot\$qtVer\build"
$qtStatic = "$qtRoot\$qtVer-static"        # <-- the keeper: qBittorrent links against this

# 1. MSVC dev environment + CMake/Ninja/Python on PATH.
& "$vsRoot\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
$env:PATH = "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;" +
            "$vsRoot\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;$python;$env:PATH"

# 2. Download Qt source (skips if already present).
if (-not (Test-Path "$src\qtbase")) {
    py -m aqt install-src windows $qtVer --archives qtbase qtsvg qttools -O $qtRoot
}

# 3. Configure + build + install static qtbase.
#    Bundled 3rd-party deps (-qt-*) -> no external CMake targets to resolve.
#    -schannel: Windows-native TLS (no OpenSSL needed by Qt). -sql-sqlite: resume storage.
$qtbaseBuild = "$buildDir\qtbase"
New-Item -ItemType Directory -Force -Path $qtbaseBuild | Out-Null
Set-Location $qtbaseBuild
& "$src\qtbase\configure.bat" -static -static-runtime -release -prefix $qtStatic `
    -nomake examples -nomake tests -schannel -sql-sqlite `
    -qt-zlib -qt-libpng -qt-libjpeg -qt-freetype -qt-harfbuzz -qt-pcre -qt-doubleconversion
if ($LASTEXITCODE -ne 0) { throw 'qtbase configure failed' }
cmake --build . --parallel
if ($LASTEXITCODE -ne 0) { throw 'qtbase build failed' }
cmake --install .
if ($LASTEXITCODE -ne 0) { throw 'qtbase install failed' }

# 4. Configure + build + install add-on modules against the static qtbase.
#    qtsvg = SVG icons (required by the GUI); qttools = lrelease (LinguistTools).
foreach ($m in @('qtsvg', 'qttools')) {
    $mb = "$buildDir\$m"
    New-Item -ItemType Directory -Force -Path $mb | Out-Null
    Set-Location $mb
    & "$qtStatic\bin\qt-configure-module.bat" "$src\$m"
    if ($LASTEXITCODE -ne 0) { throw "$m configure failed" }
    cmake --build . --parallel
    if ($LASTEXITCODE -ne 0) { throw "$m build failed" }
    cmake --install .
    if ($LASTEXITCODE -ne 0) { throw "$m install failed" }
}

Write-Host "`nStatic Qt ready -> $qtStatic" -ForegroundColor Green
Write-Host "Next: run build-static.ps1 to build qBittorrent as a single self-contained exe." -ForegroundColor Green
