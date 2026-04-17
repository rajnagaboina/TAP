param(
    [Parameter(Mandatory)][string]$AppServiceName,
    [Parameter(Mandatory)][string]$ResourceGroup
)

Write-Host ""
Write-Host "Easy Auth Validation – $AppServiceName" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# Ensure logged in
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in to Azure CLI. Running az login..." -ForegroundColor Yellow
    az login --use-device-code
    $account = az account show | ConvertFrom-Json
}
Write-Host "Subscription : $($account.name) [$($account.id)]" -ForegroundColor Gray
Write-Host ""

# ── 1. Auth settings ──────────────────────────────────────────────────────────
$authRaw = az webapp auth show `
    --name $AppServiceName `
    --resource-group $ResourceGroup 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Could not retrieve auth settings. Check the app name and resource group." -ForegroundColor Red
    Write-Host $authRaw
    exit 1
}
$auth = $authRaw | ConvertFrom-Json

# ── 2. Auth V2 settings (newer Easy Auth) ─────────────────────────────────────
$authV2Raw = az webapp auth config-version show `
    --name $AppServiceName `
    --resource-group $ResourceGroup 2>&1
$isV2 = ($authV2Raw -notmatch "error") -and (($authV2Raw | ConvertFrom-Json).configVersion -eq "v2")

# ── 3. Checks ─────────────────────────────────────────────────────────────────
$checks = @()

function Add-Check($name, $pass, $actual, $expected) {
    $checks += [PSCustomObject]@{
        Check    = $name
        Status   = if ($pass) { "PASS" } else { "FAIL" }
        Expected = $expected
        Actual   = $actual
    }
}

# 3.1 Auth enabled
Add-Check "Authentication enabled" `
    ($auth.enabled -eq $true) `
    $auth.enabled `
    $true

# 3.2 Unauthenticated action = redirect (not allow)
Add-Check "Unauthenticated action = RedirectToLoginPage" `
    ($auth.unauthenticatedClientAction -in @("RedirectToLoginPage", 0)) `
    $auth.unauthenticatedClientAction `
    "RedirectToLoginPage"

# 3.3 Token store enabled (needed for /.auth/token)
Add-Check "Token store enabled" `
    ($auth.tokenStoreEnabled -eq $true) `
    $auth.tokenStoreEnabled `
    $true

# ── 4. AAD provider details ───────────────────────────────────────────────────
if ($isV2) {
    $authDetailRaw = az webapp auth microsoft show `
        --name $AppServiceName `
        --resource-group $ResourceGroup 2>&1
    $aad = $authDetailRaw | ConvertFrom-Json

    Add-Check "AAD provider configured" `
        ($null -ne $aad) `
        $(if ($aad) { "present" } else { "missing" }) `
        "present"

    Add-Check "Client ID set" `
        (-not [string]::IsNullOrEmpty($aad.registration.clientId)) `
        $aad.registration.clientId `
        "<your UI App Registration client ID>"

    Add-Check "Issuer URL ends in /v2.0" `
        ($aad.registration.openIdIssuer -like "*microsoftonline.com*" -and $aad.registration.openIdIssuer -like "*/v2.0*") `
        $aad.registration.openIdIssuer `
        "https://login.microsoftonline.com/<tenantId>/v2.0"

    Add-Check "login scopes include access_as_user" `
        ($aad.login.loginParameters -join " " -like "*access_as_user*") `
        ($aad.login.loginParameters -join " ") `
        "...api://.../access_as_user"
} else {
    $aadSettings = $auth.additionalLoginParams

    Add-Check "AAD Active Directory provider enabled" `
        ($auth.clientId -ne $null -and $auth.clientId -ne "") `
        $auth.clientId `
        "<your UI App Registration client ID>"

    Add-Check "Issuer URL set" `
        ($auth.issuer -like "*microsoftonline.com*") `
        $auth.issuer `
        "https://login.microsoftonline.com/<tenantId>/v2.0"
}

# ── 5. Print results ──────────────────────────────────────────────────────────
Write-Host ""
$checks | Format-Table -AutoSize

$failures = $checks | Where-Object { $_.Status -eq "FAIL" }
if ($failures.Count -eq 0) {
    Write-Host "All Easy Auth checks passed." -ForegroundColor Green
} else {
    Write-Host "$($failures.Count) check(s) failed. Review the FAIL rows above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Fix guide:" -ForegroundColor Yellow
    foreach ($f in $failures) {
        switch ($f.Check) {
            "Authentication enabled"                   { Write-Host "  → Portal: App Service → Authentication → Enable" }
            "Unauthenticated action = RedirectToLoginPage" { Write-Host "  → Portal: Authentication → Unauthenticated requests → HTTP 302 Redirect" }
            "Token store enabled"                      { Write-Host "  → Portal: Authentication → Token store → ON" }
            "Issuer URL ends in /v2.0"                 { Write-Host "  → Portal: Authentication → Edit provider → Issuer URL: https://login.microsoftonline.com/<tenantId>/v2.0" }
            "login scopes include access_as_user"      { Write-Host "  → Portal: Authentication → Edit provider → Additional scopes: api://<API_CLIENT_ID>/access_as_user" }
        }
    }
}
