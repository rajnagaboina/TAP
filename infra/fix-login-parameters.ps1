$appName       = "tap"
$resourceGroup = "airg-platform-rg"
$apiClientId   = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$apiScope      = "api://$apiClientId/access_as_user"
$scopeValue    = "scope=openid profile email $apiScope"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
$subId = (az account show | ConvertFrom-Json).id

$url = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$appName/config/authsettingsV2?api-version=2022-03-01"

Write-Host "Reading current config..." -ForegroundColor Cyan
$config = az rest --method GET --url $url | ConvertFrom-Json
$aad    = $config.properties.identityProviders.azureActiveDirectory

# Set loginParameters under the AAD provider login node (correct v2 path)
if ($null -eq $aad.login) {
    $aad | Add-Member -MemberType NoteProperty -Name "login" -Value ([PSCustomObject]@{}) -Force
}
$aad.login | Add-Member `
    -MemberType NoteProperty `
    -Name "loginParameters" `
    -Value ([string[]]@($scopeValue)) `
    -Force

$bodyFile = [System.IO.Path]::GetTempFileName() + ".json"
$config | ConvertTo-Json -Depth 20 | ForEach-Object { [System.IO.File]::WriteAllText($bodyFile, $_, (New-Object System.Text.UTF8Encoding $false)) }

Write-Host "Saving (AAD provider login node)..." -ForegroundColor Cyan
az rest --method PUT --url $url `
    --headers "Content-Type=application/json" `
    --body "@$bodyFile" | Out-Null
Remove-Item $bodyFile -Force

# Verify both paths
$result = az rest --method GET --url $url | ConvertFrom-Json
$topLevel   = $result.properties.login.loginParameters
$aadLevel   = $result.properties.identityProviders.azureActiveDirectory.login.loginParameters

Write-Host ""
Write-Host "Top-level loginParameters  : $($topLevel  -join ', ')"
Write-Host "AAD-level loginParameters  : $($aadLevel  -join ', ')"

if ($topLevel -or $aadLevel) {
    Write-Host ""
    Write-Host "Login parameters saved successfully." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "API will not persist loginParameters. Set via portal instead:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Portal -> App Service 'tap' -> Authentication" -ForegroundColor White
    Write-Host "  2. Click Edit on the Microsoft provider row" -ForegroundColor White
    Write-Host "  3. Expand 'Additional checks'" -ForegroundColor White
    Write-Host "  4. Find 'Additional login parameters' field" -ForegroundColor White
    Write-Host "  5. Enter exactly:" -ForegroundColor White
    Write-Host ""
    Write-Host "     $scopeValue" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  6. Click Save" -ForegroundColor White
}
