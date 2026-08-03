# Lance le bureau KDE en local, avec GPU si le rendu GPU est REELLEMENT disponible.
# Attention : une carte detectee (nvidia-smi) ne suffit pas — il faut la capacite GRAPHIQUE.
# Usage : powershell -ExecutionPolicy Bypass -File scripts\up-local.ps1
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$probeImage = "alpine:3.20"   # sonde legere : on teste des devices/libs, pas l application
$probe = 'if [ -e /dev/dxg ] && [ -f /usr/lib/wsl/lib/libd3d12.so ]; then echo WSL; elif [ -d /dev/dri ]; then echo DRI; else echo NONE; fi'

function Get-RenderMode {
  param([string[]]$ExtraArgs)
  $args = @("run","--rm") + $ExtraArgs + @("-v","/usr/lib/wsl:/usr/lib/wsl:ro",$probeImage,"sh","-c",$probe)
  try {
    $out = & docker @args 2>$null
    # on ne garde que le verdict : le pull d image pollue la sortie
    $verdict = $out | Where-Object { $_ -match '^(WSL|DRI|NONE)\s*$' } | Select-Object -Last 1
    if ($verdict) { return $verdict.Trim() }
  } catch {}
  return "NONE"
}

# s assurer que la sonde est en cache pour ne pas polluer la sortie
& docker image inspect $probeImage *> $null
if ($LASTEXITCODE -ne 0) { & docker pull $probeImage *> $null }

Write-Host "[detect] capacite de rendu GPU..." -NoNewline
$mode = Get-RenderMode -ExtraArgs @("--gpus","all")
if ($mode -eq "NONE") { $mode = Get-RenderMode -ExtraArgs @() }

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