# =============================================================================
# 02-azure.ps1  –  Create Azure resources: App Services, App Insights, APIM.
#
# Prerequisites:
#   - 01-entra.ps1 completed successfully
#   - az cli logged in with Contributor on the subscription
#   - config.ps1 filled in
#
# Run time: ~5 minutes (APIM Consumption provisions in ~30 seconds)
# Safe to re-run.
# =============================================================================
. "$PSScriptRoot\config.ps1"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    FAIL: $msg" -ForegroundColor Red; exit 1 }

az account set --subscription $SUBSCRIPTION_ID

# ── 1. Resource Group ─────────────────────────────────────────────────────────
Write-Step "Resource Group: $RESOURCE_GROUP"
$rg = az group show --name $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $rg) {
    az group create --name $RESOURCE_GROUP --location $LOCATION | Out-Null
    Write-OK "Created: $RESOURCE_GROUP ($LOCATION)"
} else {
    Write-OK "Already exists: $RESOURCE_GROUP"
}

# ── 2. App Service Plan – API ─────────────────────────────────────────────────
Write-Step "App Service Plan (API): $APP_PLAN_API"
$planApi = az appservice plan show --name $APP_PLAN_API --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $planApi) {
    az appservice plan create `
        --name $APP_PLAN_API `
        --resource-group $RESOURCE_GROUP `
        --sku $APP_SKU `
        --is-linux false | Out-Null
    Write-OK "Created: $APP_PLAN_API ($APP_SKU Windows)"
} else {
    Write-OK "Already exists: $APP_PLAN_API"
}

# ── 3. API App Service ────────────────────────────────────────────────────────
Write-Step "API App Service: $API_APP_NAME"
$apiApp = az webapp show --name $API_APP_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $apiApp) {
    az webapp create `
        --name $API_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --plan $APP_PLAN_API `
        --runtime "DOTNET|8.0" | Out-Null
    Write-OK "Created: $API_APP_NAME"
} else {
    Write-OK "Already exists: $API_APP_NAME"
}

# Enable Always On to prevent cold starts
az webapp config set --name $API_APP_NAME --resource-group $RESOURCE_GROUP --always-on true | Out-Null
az webapp update  --name $API_APP_NAME --resource-group $RESOURCE_GROUP --https-only true  | Out-Null
$apiHostname = (az webapp show --name $API_APP_NAME --resource-group $RESOURCE_GROUP --query "defaultHostName" -o tsv)
Write-OK "Hostname: $apiHostname"

# ── 4. App Service Plan – UI ──────────────────────────────────────────────────
Write-Step "App Service Plan (UI): $APP_PLAN_UI"
$planUi = az appservice plan show --name $APP_PLAN_UI --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $planUi) {
    az appservice plan create `
        --name $APP_PLAN_UI `
        --resource-group $RESOURCE_GROUP `
        --sku $APP_SKU `
        --is-linux false | Out-Null
    Write-OK "Created: $APP_PLAN_UI ($APP_SKU Windows)"
} else {
    Write-OK "Already exists: $APP_PLAN_UI"
}

# ── 5. UI App Service ─────────────────────────────────────────────────────────
Write-Step "UI App Service: $UI_APP_NAME"
$uiApp = az webapp show --name $UI_APP_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $uiApp) {
    az webapp create `
        --name $UI_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --plan $APP_PLAN_UI | Out-Null
    Write-OK "Created: $UI_APP_NAME"
} else {
    Write-OK "Already exists: $UI_APP_NAME"
}

az webapp update --name $UI_APP_NAME --resource-group $RESOURCE_GROUP --https-only true | Out-Null
$uiHostname = (az webapp show --name $UI_APP_NAME --resource-group $RESOURCE_GROUP --query "defaultHostName" -o tsv)
Write-OK "Hostname: $uiHostname"

# ── 6. Application Insights ───────────────────────────────────────────────────
Write-Step "Application Insights: $APPINSIGHTS_NAME"
$ai = az monitor app-insights component show `
    --app $APPINSIGHTS_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $ai) {
    az monitor app-insights component create `
        --app $APPINSIGHTS_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $LOCATION `
        --kind web | Out-Null
    $ai = az monitor app-insights component show `
        --app $APPINSIGHTS_NAME --resource-group $RESOURCE_GROUP | ConvertFrom-Json
    Write-OK "Created: $APPINSIGHTS_NAME"
} else {
    Write-OK "Already exists: $APPINSIGHTS_NAME"
}
$AI_CONN_STR = $ai.connectionString
Write-OK "Connection string captured"

# ── 7. APIM (Consumption) ─────────────────────────────────────────────────────
Write-Step "APIM: $APIM_NAME (Consumption)"
$apim = az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $apim) {
    Write-Host "    Creating APIM (~30 seconds)..." -ForegroundColor Gray
    az apim create `
        --name $APIM_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $LOCATION `
        --publisher-email $APIM_EMAIL `
        --publisher-name $APIM_ORG `
        --sku-name Consumption | Out-Null
    Write-OK "Created: $APIM_NAME"
} else {
    Write-OK "Already exists: $APIM_NAME"
}
$apimGateway = (az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP --query "gatewayUrl" -o tsv)
Write-OK "Gateway URL: $apimGateway"

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "AZURE INFRA COMPLETE" -ForegroundColor Green
Write-Host "  API App Service : https://$apiHostname"
Write-Host "  UI  App Service : https://$uiHostname"
Write-Host "  APIM Gateway    : $apimGateway"
Write-Host "  App Insights    : $APPINSIGHTS_NAME"
Write-Host "  AI Conn String  : $($AI_CONN_STR.Substring(0,40))..."
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Save outputs for next script
@{
    API_HOSTNAME = $apiHostname
    UI_HOSTNAME  = $uiHostname
    APIM_GATEWAY = $apimGateway
    AI_CONN_STR  = $AI_CONN_STR
} | ConvertTo-Json | Set-Content "$PSScriptRoot\.infra-outputs.json"

Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Validate: curl https://$apiHostname/health  (should return 'Healthy' after deploy)"
Write-Host "  2. Run: .\deploy\03-configure.ps1"
