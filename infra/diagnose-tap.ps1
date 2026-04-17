#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Diagnoses why temporaryAccessPass is null from Graph.
  - Verifies MI has UserAuthenticationMethod.ReadWrite.All
  - Checks if TAP auth method is enabled in the tenant policy
  - Lists and optionally deletes existing TAPs for a test user
  - Enables App Service application logging

.PARAMETER TestUserUpn
  UPN of the user to check for existing TAPs (e.g. intune@nagaboina1983.onmicrosoft.com)

.PARAMETER DeleteExistingTaps
  If specified, deletes any existing TAPs for TestUserUpn before testing.

.PARAMETER EnableAppLogging
  If specified, enables App Service application logging (filesystem, verbose).
#>
param(
    [string]$TestUserUpn = "intune@nagaboina1983.onmicrosoft.com",
    [switch]$DeleteExistingTaps,
    [switch]$EnableAppLogging
)

$ErrorActionPreference = "Stop"

$MiObjectId         = "5906180b-d377-4856-aacf-1b09cba28655"
$ResourceGroup      = "airg-platform-rg"
$ApiAppServiceName  = "asp-tap-generator-api"

Write-Host "`n=== TAP Generator Diagnostics ===" -ForegroundColor Cyan

# ── 1. Check MI app role assignments ──────────────────────────────────────────
Write-Host "`n[1] Checking MI app role assignments..." -ForegroundColor Yellow

$graphSpId = (az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query "[0].id" -o tsv 2>$null).Trim()
if (-not $graphSpId) {
    Write-Host "  WARN: Could not find Microsoft Graph service principal via az cli. Trying mg..." -ForegroundColor Yellow
}
else {
    Write-Host "  Microsoft Graph SP: $graphSpId"
    $assignments = az rest `
        --method GET `
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/$MiObjectId/appRoleAssignments" `
        --headers "Content-Type=application/json" `
        | ConvertFrom-Json

    $targetRoleId = "50483e42-d915-4231-9212-7572167b5e36"  # UserAuthenticationMethod.ReadWrite.All

    $found = $assignments.value | Where-Object { $_.appRoleId -eq $targetRoleId }
    if ($found) {
        Write-Host "  [OK] UserAuthenticationMethod.ReadWrite.All is assigned to MI" -ForegroundColor Green
        Write-Host "       Assignment ID: $($found.id)"
        Write-Host "       Assigned: $($found.createdDateTime)"
    }
    else {
        Write-Host "  [MISSING] UserAuthenticationMethod.ReadWrite.All NOT found on MI!" -ForegroundColor Red
        Write-Host "  Assigning it now..."
        $body = @{
            principalId = $MiObjectId
            resourceId  = $graphSpId
            appRoleId   = $targetRoleId
        } | ConvertTo-Json -Compress

        az rest `
            --method POST `
            --url "https://graph.microsoft.com/v1.0/servicePrincipals/$MiObjectId/appRoleAssignments" `
            --headers "Content-Type=application/json" `
            --body $body | Out-Null
        Write-Host "  [DONE] Permission granted." -ForegroundColor Green
    }
}

# ── 2. Check TAP auth method policy ───────────────────────────────────────────
Write-Host "`n[2] Checking TAP authentication method policy in tenant..." -ForegroundColor Yellow

$tapPolicy = az rest `
    --method GET `
    --url "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/TemporaryAccessPass" `
    --headers "Content-Type=application/json" `
    | ConvertFrom-Json

Write-Host "  TAP Policy State: $($tapPolicy.state)"
Write-Host "  Default Lifetime: $($tapPolicy.defaultLifetimeInMinutes) minutes"
Write-Host "  Is Usable Once default: $($tapPolicy.isUsableOnce)"
Write-Host "  Minimum Lifetime: $($tapPolicy.minimumLifetimeInMinutes) minutes"
Write-Host "  Maximum Lifetime: $($tapPolicy.maximumLifetimeInMinutes) minutes"

if ($tapPolicy.state -ne "enabled") {
    Write-Host "  [WARN] TAP auth method is DISABLED in this tenant!" -ForegroundColor Red
    Write-Host "  To enable: Entra ID -> Security -> Authentication methods -> Temporary Access Pass -> Enable"
}
else {
    Write-Host "  [OK] TAP is enabled in this tenant" -ForegroundColor Green
}

# ── 3. List (and optionally delete) existing TAPs for test user ───────────────
Write-Host "`n[3] Listing existing TAPs for $TestUserUpn..." -ForegroundColor Yellow

$taps = az rest `
    --method GET `
    --url "https://graph.microsoft.com/v1.0/users/$TestUserUpn/authentication/temporaryAccessPassMethods" `
    --headers "Content-Type=application/json" `
    | ConvertFrom-Json

if ($taps.value.Count -eq 0) {
    Write-Host "  No existing TAPs found for $TestUserUpn" -ForegroundColor Green
}
else {
    foreach ($tap in $taps.value) {
        $expires = if ($tap.startDateTime) {
            [datetime]::Parse($tap.startDateTime).AddMinutes($tap.lifetimeInMinutes)
        } else { "unknown" }
        Write-Host "  TAP ID: $($tap.id)" -ForegroundColor Yellow
        Write-Host "    Lifetime: $($tap.lifetimeInMinutes) min"
        Write-Host "    Started:  $($tap.startDateTime)"
        Write-Host "    Expires:  $expires"
        Write-Host "    IsUsable: $($tap.isUsable)"
        Write-Host "    Reason:   $($tap.methodUsabilityReason)"

        if ($DeleteExistingTaps) {
            Write-Host "    Deleting TAP $($tap.id)..." -ForegroundColor Yellow
            az rest `
                --method DELETE `
                --url "https://graph.microsoft.com/v1.0/users/$TestUserUpn/authentication/temporaryAccessPassMethods/$($tap.id)" `
                --headers "Content-Type=application/json"
            Write-Host "    [DELETED]" -ForegroundColor Green
        }
    }

    if (-not $DeleteExistingTaps) {
        Write-Host "`n  --> Re-run with -DeleteExistingTaps to remove them before testing" -ForegroundColor Cyan
    }
}

# ── 4. Enable App Service application logging ─────────────────────────────────
if ($EnableAppLogging) {
    Write-Host "`n[4] Enabling App Service application logging..." -ForegroundColor Yellow
    az webapp log config `
        --name $ApiAppServiceName `
        --resource-group $ResourceGroup `
        --application-logging filesystem `
        --level verbose
    Write-Host "  [OK] Application logging enabled (filesystem, verbose)" -ForegroundColor Green
    Write-Host "  View logs: az webapp log tail --name $ApiAppServiceName --resource-group $ResourceGroup"
}
else {
    Write-Host "`n[4] Skipped App logging setup (add -EnableAppLogging to enable)" -ForegroundColor Gray
}

Write-Host "`n=== Done ===`n" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. If TAP policy is disabled → enable it in the portal" -ForegroundColor White
Write-Host "  2. If existing TAPs found → re-run with -DeleteExistingTaps" -ForegroundColor White
Write-Host "  3. Run with -EnableAppLogging, then tail logs while generating a TAP:" -ForegroundColor White
Write-Host "     az webapp log tail --name $ApiAppServiceName --resource-group $ResourceGroup" -ForegroundColor DarkGray
