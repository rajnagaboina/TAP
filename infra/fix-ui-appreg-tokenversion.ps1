$uiClientId = "ba9431f0-539e-48d9-9893-75a21716d6ae"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code

# Get the app's Object ID (different from Client/App ID)
$objectId = az ad app show --id $uiClientId --query id -o tsv
Write-Host "App Object ID: $objectId" -ForegroundColor Gray

# PATCH via Graph API – set requestedAccessTokenVersion = 2
Write-Host ""
Write-Host "Setting accessTokenAcceptedVersion = 2..." -ForegroundColor Cyan

$bodyFile = [System.IO.Path]::GetTempFileName() + ".json"
'{"api": {"requestedAccessTokenVersion": 2}}' | ForEach-Object { [System.IO.File]::WriteAllText($bodyFile, $_, (New-Object System.Text.UTF8Encoding $false)) }

az rest --method PATCH `
    --url "https://graph.microsoft.com/v1.0/applications/$objectId" `
    --headers "Content-Type=application/json" `
    --body "@$bodyFile"
Remove-Item $bodyFile -Force

if ($LASTEXITCODE -eq 0) {
    $version = az ad app show --id $uiClientId --query "api.requestedAccessTokenVersion" -o tsv
    Write-Host ""
    Write-Host "Verified accessTokenAcceptedVersion: $version" -ForegroundColor Green
    Write-Host "UI App Registration fix complete." -ForegroundColor Green
} else {
    Write-Host "PATCH failed." -ForegroundColor Red
}
