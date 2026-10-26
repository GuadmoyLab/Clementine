# Installs Clementine for the current user: %LOCALAPPDATA%\Programs\Clementine
#   .\install.ps1              build if needed, copy, add Start menu shortcut and Explorer right-click action
#   .\install.ps1 -Uninstall   remove all of it
param([switch]$Uninstall)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA "Programs\Clementine"
$exe = Join-Path $dest "clementine.exe"
$lnk = Join-Path ([Environment]::GetFolderPath("Programs")) "Clementine.lnk"
$key = "HKCU:\Software\Classes\*\shell\Clementine"

if ($Uninstall) {
    Remove-Item -Recurse -Force $dest, $lnk -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $key -ErrorAction SilentlyContinue
    Write-Host "Uninstalled"
    return
}

if (-not (Test-Path dist\Clementine\clementine.exe)) { .\build.ps1 }
Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
Copy-Item -Recurse dist\Clementine $dest

$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk); $s.TargetPath = $exe; $s.Save()

# Explorer: right-click a file. With several files selected Explorer starts one process
# per file (the "single document model" limit), so use the Shift+drag / drop-on-window route for batches.
New-Item -Force $key | Out-Null
Set-ItemProperty $key "(default)" "Convert with Clementine"
Set-ItemProperty $key "Icon" $exe
New-Item -Force "$key\command" | Out-Null
Set-ItemProperty "$key\command" "(default)" "`"$exe`" `"%1`""

Write-Host "Installed to $dest"
