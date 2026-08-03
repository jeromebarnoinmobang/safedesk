# Forge locale d un APK SafeDesk (Windows). Rien en dur : tout est parametrable.
#   powershell -ExecutionPolicy Bypass -File scripts\build-apk.ps1 [options]
# Options :
#   -Src <dossier>     projet gradle a construire   (defaut: <repo>\android)
#   -Task <tache>      tache gradle                 (defaut: assembleRelease)
#   -Out <dossier>     ou deposer l APK             (defaut: <repo>\dist)
#   -Name <nom>        nom du fichier final         (defaut: SafeDesk-local.apk)
#   -WithNdk           builder avec NDK (clients natifs)
# La cle de signature locale vit dans le volume docker "safedesk-keys" :
# STABLE -> les mises a jour s installent par-dessus, memes appareils.
param(
  [string]$Src  = "",
  [string]$Task = "assembleRelease",
  [string]$Out  = "",
  [string]$Name = "SafeDesk-local.apk",
  [switch]$WithNdk
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Src) { $Src = Join-Path $repo "android" }
if (-not $Out) { $Out = Join-Path $repo "dist" }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$img = "safedesk/android-builder"
if ($WithNdk) { $img = "safedesk/android-builder:ndk" }
$exists = docker image inspect $img 2>$null
if (-not $exists) {
  Write-Host "[forge] construction du forgeron ($img)... (une seule fois)"
  $ndkArg = if ($WithNdk) { "true" } else { "false" }
  docker build -t $img --build-arg WITH_NDK=$ndkArg (Join-Path $repo "builder")
  if ($LASTEXITCODE -ne 0) { throw "echec construction du forgeron" }
}

Write-Host "[forge] $Task sur $Src"
docker run --rm `
  -v "${Src}:/src" `
  -v "safedesk-gradle-cache:/root/.gradle" `
  -v "safedesk-keys:/keys" `
  -w /src $img sh -c @"
set -e
gradle --quiet $Task
KS=/keys/safedesk-local.jks
if [ ! -f `$KS ]; then
  PASS=`$(head -c 24 /dev/urandom | base64 | tr -dc A-Za-z0-9 | cut -c1-24)
  keytool -genkeypair -keystore `$KS -storepass "`$PASS" -keypass "`$PASS" \
    -alias safedesk -dname CN=SafeDesk -keyalg RSA -keysize 2048 -validity 3650
  echo "`$PASS" > /keys/.pass; chmod 600 /keys/.pass
  echo '[forge] cle locale STABLE creee (volume safedesk-keys)'
fi
PASS=`$(cat /keys/.pass)
BT=`$(ls -d /opt/android-sdk/build-tools/* | sort -V | tail -1)
APK=`$(find . -path '*outputs/apk*' -name '*.apk' | head -1)
`$BT/zipalign -f -p 4 "`$APK" /tmp/aligned.apk
`$BT/apksigner sign --ks `$KS --ks-pass pass:`$PASS --ks-key-alias safedesk \
  --key-pass pass:`$PASS --out /src/.forge-out.apk /tmp/aligned.apk
"@
if ($LASTEXITCODE -ne 0) { throw "echec de la forge" }
Move-Item -Force (Join-Path $Src ".forge-out.apk") (Join-Path $Out $Name)
Write-Host "[forge] OK -> $(Join-Path $Out $Name)" -ForegroundColor Green