$appName       = "tap"
$resourceGroup = "airg-platform-rg"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
$subId = (az account show | ConvertFrom-Json).id

$url = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$appName/config/authsettingsV2?api-version=2022-03-01"

Write-Host "Reading current config..." -ForegroundColor Cyan
$config = az rest --method GET --url $url | ConvertFrom-Json

# Change unauthenticated action to AllowAnonymous so static assets load freely.
# Flutter handles the redirect to /.auth/login/aad when /.auth/me returns no user.
$config.properties.globalValidation.unauthenticatedClientAction = "AllowAnonymous"

$bodyFile = [System.IO.Path]::GetTempFileName() + ".json"
$config | ConvertTo-Json -Depth 20 | ForEach-Object {
    [System.IO.File]::WriteAllText($bodyFile, $_, (New-Object System.Text.UTF8Encoding $false))
}

Write-Host "Saving..." -ForegroundColor Cyan
az rest --method PUT --url $url --headers "Content-Type=application/json" --body "@$bodyFile" | Out-Null
Remove-Item $bodyFile -Force

if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to update." -ForegroundColor Red; exit 1 }

$result = (az rest --method GET --url $url | ConvertFrom-Json).properties.globalValidation.unauthenticatedClientAction
Write-Host "unauthenticatedClientAction: $result" -ForegroundColor Green
Write-Host "Easy Auth updated." -ForegroundColor Green
