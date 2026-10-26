# Builds Clementine on Windows and bundles Qt next to the exe: dist\Clementine\
# Needs: Rust (MSVC toolchain), Qt 6 for MSVC (QTDIR or qmake6 in PATH), Visual Studio Build Tools.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

foreach ($t in "cargo", "qmake6") {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "missing build requirement: $t" }
}
foreach ($t in "magick", "ffmpeg", "pdftoppm") {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Write-Warning "'$t' not found in PATH, the matching conversions will report an error" }
}

cargo build --release
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

$dist = "dist\Clementine"
Remove-Item -Recurse -Force $dist -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dist | Out-Null
Copy-Item target\release\clementine.exe $dist
windeployqt6 --release --qmldir qml "$dist\clementine.exe"
if ($LASTEXITCODE -ne 0) { throw "windeployqt6 failed" }
Write-Host "Built: $PWD\$dist\clementine.exe"
