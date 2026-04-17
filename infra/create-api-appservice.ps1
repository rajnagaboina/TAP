$resourceGroup   = "airg-platform-rg"
$appName         = "asp-tap-generator-api"
$tenantId        = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId     = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$appInsightsConn = "InstrumentationKey=9e1cf43c-8815-44d6-90f5-6815042f5f80;IngestionEndpoint=https://westus2-2.in.applicationinsights.azure.com/;LiveEndpoint=https://westus2.livediagnostics.monitor.azure.com/;ApplicationId=e44f3b3c-da9a-4c5f-8b4a-661a1b105fbd"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
az account show

# Verify app exists
$app = az webapp show --name $appName --resource-group $resourceGroup 2>$null | ConvertFrom-Json
if (-not $app) { Write-Host "ERROR: $appName not found in $resourceGroup" -ForegroundColor Red; exit 1 }
Write-Host "Found App Service: $appName" -ForegroundColor Green

# ── 1. Enable system-assigned Managed Identity ───────────────────────────────
Write-Host ""
Write-Host "Enabling system-assigned Managed Identity..." -ForegroundColor Cyan
$mi = az webapp identity assign `
    --name $appName `
    --resource-group $resourceGroup | ConvertFrom-Json
$miObjectId = $mi.principalId
Write-Host "MI Object ID: $miObjectId" -ForegroundColor Green

# ── 2. App Settings ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Configuring App Settings..." -ForegroundColor Cyan
az webapp config appsettings set `
    --name $appName `
    --resource-group $resourceGroup `
    --settings `
        "AzureAd__TenantId=$tenantId" `
        "AzureAd__Audience=api://$apiClientId" `
        "AzureAd__Instance=https://login.microsoftonline.com/" `
        "ApplicationInsights__ConnectionString=$appInsightsConn" `
        "ASPNETCORE_ENVIRONMENT=Production" `
        "WEBSITE_RUN_FROM_PACKAGE=1"
Write-Host "App Settings configured." -ForegroundColor Green

# ── 3. HTTPS only ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Enforcing HTTPS only..." -ForegroundColor Cyan
az webapp update `
    --name $appName `
    --resource-group $resourceGroup `
    --https-only true | Out-Null
Write-Host "HTTPS only enabled." -ForegroundColor Green

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuration complete" -ForegroundColor Green
Write-Host "Name         : $appName"
Write-Host "URL          : https://$appName.azurewebsites.net"
Write-Host "MI Object ID : $miObjectId"
Write-Host "========================================" -ForegroundColor Cyan
