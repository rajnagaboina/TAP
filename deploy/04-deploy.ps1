# =============================================================================
# 04-deploy.ps1  –  Build and deploy API + UI directly to Azure App Service.
#                   No GitHub Actions required.
#
# Prerequisites:
#   - 03-configure.ps1 completed
#   - dotnet SDK installed  (dotnet --version)
#   - Flutter SDK installed  (flutter --version)
#   - az cli logged in
#
# Run time: ~5 minutes
# Safe to re-run.
# =============================================================================
. "$PSScriptRoot\config.ps1"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    FAIL: $msg" -ForegroundColor Red; exit 1 }

az account set --subscription $SUBSCRIPTION_ID

# Load hostnames from infra outputs
$outputs      = Get-Content "$PSScriptRoot\.infra-outputs.json" | ConvertFrom-Json
$API_HOSTNAME = $outputs.API_HOSTNAME
$UI_HOSTNAME  = $outputs.UI_HOSTNAME

# Load Entra IDs
$API_CLIENT_ID = (az ad app list --display-name $API_APP_REG_NAME --query "[0].appId" -o tsv)
$UI_CLIENT_ID  = (az ad app list --display-name $UI_APP_REG_NAME  --query "[0].appId" -o tsv)
$APIM_GATEWAY  = $outputs.APIM_GATEWAY

if (-not $API_CLIENT_ID) { Write-Fail "API app registration not found. Run 01-entra.ps1." }
if (-not $UI_CLIENT_ID)  { Write-Fail "UI app registration not found. Run 01-entra.ps1." }

$REPO_ROOT = (Resolve-Path "$PSScriptRoot\..").Path
$TMP       = "$env:TEMP\tap-deploy"
New-Item -ItemType Directory -Force -Path $TMP | Out-Null

# ── 1. Build & deploy .NET API ────────────────────────────────────────────────
Write-Step "Building .NET API"

$API_PROJECT = "$REPO_ROOT\api\TapGenerator.Api\TapGenerator.Api.csproj"
if (-not (Test-Path $API_PROJECT)) { Write-Fail "Project not found: $API_PROJECT" }

$API_PUBLISH = "$TMP\api-publish"
Remove-Item $API_PUBLISH -Recurse -Force -ErrorAction SilentlyContinue

dotnet publish $API_PROJECT `
    --configuration Release `
    --output $API_PUBLISH `
    --runtime win-x86 `
    --self-contained false
if ($LASTEXITCODE -ne 0) { Write-Fail "dotnet publish failed" }
Write-OK "API published to $API_PUBLISH"

# Zip the publish output
$API_ZIP = "$TMP\api.zip"
Remove-Item $API_ZIP -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$API_PUBLISH\*" -DestinationPath $API_ZIP -Force
Write-OK "API zipped: $API_ZIP"

Write-Step "Deploying .NET API to $API_APP_NAME"
az webapp deploy `
    --name $API_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --src-path $API_ZIP `
    --type zip `
    --restart true
if ($LASTEXITCODE -ne 0) { Write-Fail "API deployment failed" }
Write-OK "API deployed to https://$API_HOSTNAME"

# ── 2. Build & deploy Flutter UI ──────────────────────────────────────────────
Write-Step "Building Flutter UI"

$UI_PROJECT = "$REPO_ROOT\ui"
if (-not (Test-Path "$UI_PROJECT\pubspec.yaml")) { Write-Fail "Flutter project not found: $UI_PROJECT" }

Push-Location $UI_PROJECT
    flutter build web --release `
        --dart-define=APIM_BASE_URL="$APIM_GATEWAY" `
        --dart-define=TENANT_ID="$TENANT_ID" `
        --dart-define=UI_CLIENT_ID="$UI_CLIENT_ID" `
        --dart-define=API_CLIENT_ID="$API_CLIENT_ID"
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "flutter build web failed" }
Pop-Location
Write-OK "Flutter build complete"

# Zip the web build
$UI_BUILD = "$UI_PROJECT\build\web"
$UI_ZIP   = "$TMP\ui.zip"
Remove-Item $UI_ZIP -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$UI_BUILD\*" -DestinationPath $UI_ZIP -Force
Write-OK "UI zipped: $UI_ZIP"

Write-Step "Deploying Flutter UI to $UI_APP_NAME"
az webapp deploy `
    --name $UI_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --src-path $UI_ZIP `
    --type zip `
    --restart true
if ($LASTEXITCODE -ne 0) { Write-Fail "UI deployment failed" }
Write-OK "UI deployed to https://$UI_HOSTNAME"

# ── 3. Wait for apps to restart ───────────────────────────────────────────────
Write-Step "Waiting for apps to come back up (30s)..."
Start-Sleep -Seconds 30

# Quick health check
try {
    $health = Invoke-RestMethod "https://$API_HOSTNAME/health" -TimeoutSec 20
    if ($health -eq "Healthy") { Write-OK "API /health = Healthy" }
    else { Write-Host "    [WARN] API /health = $health" -ForegroundColor Yellow }
} catch {
    Write-Host "    [WARN] API health check failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "  API : https://$API_HOSTNAME"
Write-Host "  UI  : https://$UI_HOSTNAME"
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  Run: .\deploy\05-validate.ps1"
