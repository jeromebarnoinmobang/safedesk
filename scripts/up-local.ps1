# Lance le bureau KDE en local, avec GPU si le rendu GPU est REELLEMENT disponible.
# Attention : une carte detectee (nvidia-smi) ne suffit pas — il faut la capacite GRAPHIQUE.
# Usage : powershell -ExecutionPolicy Bypass -File scripts\up-local.ps1
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$image = (Select-String -Path "$repo\docker-compose.yml" -Pattern '^\s*image:\s*(\S*webtop\S*)' |
          Select-Object -First 1).Matches.Groups[1].Value

$probe = 'if [ -e /dev/dxg ] && [ -f /usr/lib/wsl/lib/libd3d12.so ]; then echo WSL; elif [ -d /dev/dri ]; then echo DRI; else echo NONE; fi'

Write-Host "[detect] capacite de rendu GPU..." -NoNewline
$mode = "NONE"
try {
  $out = & docker run --rm --gpus all -v /usr/lib/wsl:/usr/lib/wsl:ro `
           --entrypoint sh $image -c $probe 2>$null
  if ($LASTEXITCODE -eq 0 -and $out) { $mode = ($out | Select-Object -Last 1).Trim() }
} catch { $mode = "NONE" }
# sans --gpus (hote Linux avec /dev/dri seulement)
if ($mode -eq "NONE") {
  try {
    $out = & docker run --rm --entrypoint sh $image -c $probe 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { $mode = ($out | Select-Object -Last 1).Trim() }
  } catch {}
}

$files = @("-f","docker-compose.yml","-f","docker-compose.local.yml")
switch ($mode) {
  "WSL" { Write-Host " GPU via WSL2/d3d12" -ForegroundColor Green
          $env:RENDER_PROFILE="zz-gpu-wsl"; $files += @("-f","docker-compose.gpu-wsl.yml") }
  "DRI" { Write-Host " GPU via /dev/dri" -ForegroundColor Green
          $env:RENDER_PROFILE="zz-gpu-dri"; $files += @("-f","docker-compose.gpu-dri.yml") }
  default { Write-Host " aucun rendu GPU -> rendu logiciel" -ForegroundColor Yellow
            $env:RENDER_PROFILE="zz-no-gpu" }
}

& docker compose @files up -d
if ($LASTEXITCODE -ne 0) { throw "docker compose up a echoue" }
Write-Host ""
Write-Host "Bureau : http://localhost:3000   (rendu : $($env:RENDER_PROFILE))" -ForegroundColor Cyan