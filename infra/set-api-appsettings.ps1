$apiAppName    = "asp-tap-generator-api"
$resourceGroup = "airg-platform-rg"
$tenantId      = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId   = "6b1a0438-1405-45dc-a09c-d3282d41e37c"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code

Write-Host ""
Write-Host "Setting API App Service application settings..." -ForegroundColor Cyan

az webapp config appsettings set `
    --name $apiAppName `
    --resource-group $resourceGroup `
    --settings `
        "AzureAd__TenantId=$tenantId" `
        "AzureAd__Audience=api://$apiClientId" `
        "AzureAd__Instance=https://login.microsoftonline.com/" `
        "ASPNETCORE_ENVIRONMENT=Production" | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to set app settings." -ForegroundColor Red; exit 1
}

Write-Host "Verifying..." -ForegroundColor Cyan
$settings    = az webapp config appsettings list --name $apiAppName --resource-group $resourceGroup | ConvertFrom-Json
$settingsMap = @{}; $settings | ForEach-Object { $settingsMap[$_.name] = $_.value }

Write-Host "AzureAd__TenantId    : $($settingsMap['AzureAd__TenantId'])"
Write-Host "AzureAd__Audience    : $($settingsMap['AzureAd__Audience'])"
Write-Host "AzureAd__Instance    : $($settingsMap['AzureAd__Instance'])"
Write-Host "ASPNETCORE_ENVIRONMENT: $($settingsMap['ASPNETCORE_ENVIRONMENT'])"
Write-Host ""
Write-Host "API App Settings configured." -ForegroundColor Green
