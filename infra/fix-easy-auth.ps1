$appName      = "tap"
$resourceGroup = "airg-platform-rg"
$uiClientId   = "ba9431f0-539e-48d9-9893-75a21716d6ae"
$tenantId     = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId  = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$issuerUrl    = "https://login.microsoftonline.com/$tenantId/v2.0"
$apiScope     = "api://$apiClientId/access_as_user"

# Helper: set a property, adding it if missing
function Set-Prop($obj, $name, $value) {
    if ($null -eq $obj.$name) {
        $obj | Add-Member -MemberType NoteProperty -Name $name -Value $value -Force
    } else {
        $obj.$name = $value
    }
}

# Helper: ensure a nested object exists, return it
function Initialize-Obj($obj, $name) {
    if ($null -eq $obj.$name) {
        $obj | Add-Member -MemberType NoteProperty -Name $name -Value ([PSCustomObject]@{}) -Force
    }
    return $obj.$name
}

Write-Host "Logging in to Azure CLI..." -ForegroundColor Cyan
az login --use-device-code
$subId = (az account show | ConvertFrom-Json).id
Write-Host "Subscription: $subId" -ForegroundColor Gray

$url = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$appName/config/authsettingsV2?api-version=2022-03-01"

Write-Host ""
Write-Host "Reading current Easy Auth config..." -ForegroundColor Cyan
$current = az rest --method GET --url $url | ConvertFrom-Json
$p = $current.properties

Write-Host "Applying settings..." -ForegroundColor Cyan

# ── platform ──────────────────────────────────────────────────────────────────
$platform = Initialize-Obj $p "platform"
Set-Prop $platform "enabled" $true

# ── globalValidation ──────────────────────────────────────────────────────────
$gv = Initialize-Obj $p "globalValidation"
Set-Prop $gv "unauthenticatedClientAction" "RedirectToLoginPage"

# ── identityProviders.azureActiveDirectory ────────────────────────────────────
$idp  = Initialize-Obj $p "identityProviders"
$aad  = Initialize-Obj $idp "azureActiveDirectory"
Set-Prop $aad "enabled" $true

$reg  = Initialize-Obj $aad "registration"
Set-Prop $reg "clientId"       $uiClientId
Set-Prop $reg "openIdIssuer"   $issuerUrl

$val  = Initialize-Obj $aad "validation"
Set-Prop $val "allowedAudiences" @("api://$apiClientId")

# ── login.loginParameters ─────────────────────────────────────────────────────
$login = Initialize-Obj $p "login"
Set-Prop $login "loginParameters" @("scope=openid profile email $apiScope")

# ── login.tokenStore ──────────────────────────────────────────────────────────
$tokenStore = Initialize-Obj $login "tokenStore"
Set-Prop $tokenStore "enabled" $true

# ── PUT back ──────────────────────────────────────────────────────────────────
$bodyFile = [System.IO.Path]::GetTempFileName() + ".json"
$current | ConvertTo-Json -Depth 20 | ForEach-Object { [System.IO.File]::WriteAllText($bodyFile, $_, (New-Object System.Text.UTF8Encoding $false)) }

Write-Host "Saving config..." -ForegroundColor Cyan
az rest --method PUT --url $url `
    --headers "Content-Type=application/json" `
    --body "@$bodyFile" | Out-Null
Remove-Item $bodyFile -Force

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to update Easy Auth config." -ForegroundColor Red; exit 1
}

# ── Verify ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
$r  = (az rest --method GET --url $url | ConvertFrom-Json).properties
Write-Host "Enabled          : $($r.platform.enabled)"
Write-Host "Unauth action    : $($r.globalValidation.unauthenticatedClientAction)"
Write-Host "Token store      : $($r.login.tokenStore.enabled)"
Write-Host "Client ID        : $($r.identityProviders.azureActiveDirectory.registration.clientId)"
Write-Host "Issuer           : $($r.identityProviders.azureActiveDirectory.registration.openIdIssuer)"
Write-Host "Login parameters : $($r.login.loginParameters -join ', ')"
Write-Host ""
Write-Host "Easy Auth fix complete." -ForegroundColor Green
