$uiClientId  = "ba9431f0-539e-48d9-9893-75a21716d6ae"
$apiClientId = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$sgObjectId  = "d7e09499-ac05-4053-b4d0-2f0f71822976"
$uiAppName   = "tap"

$results = [System.Collections.ArrayList]@()
function Check($area, $name, $pass, $actual, $expected, $fix) {
    $null = $results.Add([PSCustomObject]@{
        Area = $area; Check = $name
        Status = if ($pass) {"PASS"} else {"FAIL"}
        Actual = "$actual"; Fix = if ($pass) {""} else {$fix}
    })
}

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
az account show | Out-Null

# ── UI App Registration ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "[1/3] UI App Registration ($uiClientId)" -ForegroundColor Cyan
$uiApp = az ad app show --id $uiClientId | ConvertFrom-Json

# accessTokenAcceptedVersion = 2
$tokenVer = $uiApp.api.requestedAccessTokenVersion
Check "UI App Reg" "accessTokenAcceptedVersion = 2" ($tokenVer -eq 2) $tokenVer 2 `
    "Portal: TAP Generator UI → Manifest → set `"accessTokenAcceptedVersion`": 2"

# TAP.Generator app role
$tapRole = $uiApp.appRoles | Where-Object { $_.value -eq "TAP.Generator" -and $_.isEnabled }
Check "UI App Reg" "TAP.Generator app role" ($null -ne $tapRole) `
    $(if ($tapRole) {"present"} else {"missing"}) "present" `
    "Portal: TAP Generator UI → App roles → Add role (value=TAP.Generator, allowedMemberTypes=User)"

# Redirect URI for Easy Auth callback
$allRedirects = ($uiApp.web.redirectUris + $uiApp.spa.redirectUris) -join "|"
$callbackUrl  = "https://$uiAppName"
Check "UI App Reg" "Easy Auth redirect URI" ($allRedirects -like "*$callbackUrl*") `
    $allRedirects "https://$uiAppName.azurewebsites.net/.auth/login/aad/callback" `
    "Portal: TAP Generator UI → Authentication → Web → Add redirect URI: https://$uiAppName.azurewebsites.net/.auth/login/aad/callback"

# ── API App Registration ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/3] API App Registration ($apiClientId)" -ForegroundColor Cyan
$apiApp = az ad app show --id $apiClientId | ConvertFrom-Json

# accessTokenAcceptedVersion = 2
$apiTokenVer = $apiApp.api.requestedAccessTokenVersion
Check "API App Reg" "accessTokenAcceptedVersion = 2" ($apiTokenVer -eq 2) $apiTokenVer 2 `
    "Portal: TAP Generator API → Manifest → set `"accessTokenAcceptedVersion`": 2"

# App ID URI
$appIdUri    = "api://$apiClientId"
$uriPresent  = $apiApp.identifierUris -contains $appIdUri
Check "API App Reg" "App ID URI = api://<clientId>" $uriPresent `
    ($apiApp.identifierUris -join ",") $appIdUri `
    "Portal: TAP Generator API → Expose an API → Set Application ID URI to api://$apiClientId"

# access_as_user scope
$scope = $apiApp.api.oauth2PermissionScopes | Where-Object { $_.value -eq "access_as_user" -and $_.isEnabled }
Check "API App Reg" "access_as_user scope" ($null -ne $scope) `
    $(if ($scope) {"present"} else {"missing"}) "present" `
    "Portal: TAP Generator API → Expose an API → Add scope: access_as_user"

# ── Enterprise App: group role assignment ─────────────────────────────────────
Write-Host ""
Write-Host "[3/3] Security Group role assignment" -ForegroundColor Cyan
$uiSpId      = (az ad sp show --id $uiClientId | ConvertFrom-Json).id
$assignments = az rest --method GET `
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$uiSpId/appRoleAssignedTo" `
    2>$null | ConvertFrom-Json
$sgAssigned  = $assignments.value | Where-Object { $_.principalId -eq $sgObjectId }
Check "Security Group" "SG-IAM-TAP-Generators has TAP.Generator role" ($null -ne $sgAssigned) `
    $(if ($sgAssigned) {"assigned"} else {"missing"}) "assigned" `
    "Portal: Enterprise Apps → TAP Generator UI → Users and groups → Add SG-IAM-TAP-Generators → role TAP.Generator"

# ── admin consent for access_as_user ─────────────────────────────────────────
$grants      = az rest --method GET `
    --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$uiSpId'" `
    2>$null | ConvertFrom-Json
$hasConsent  = $grants.value | Where-Object { $_.scope -like "*access_as_user*" }
Check "UI App Reg" "access_as_user admin consent granted" ($null -ne $hasConsent) `
    $(if ($hasConsent) {"granted"} else {"missing"}) "granted" `
    "Portal: TAP Generator UI → API Permissions → Grant admin consent for <tenant>"

# ── Results ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
$results | Format-Table Area, Check, Status, Actual -AutoSize

$fails = $results | Where-Object { $_.Status -eq "FAIL" }
$pass  = $results | Where-Object { $_.Status -eq "PASS" }
Write-Host "PASS: $($pass.Count)   FAIL: $($fails.Count)" -ForegroundColor $(if ($fails.Count -eq 0) {"Green"} else {"Yellow"})

if ($fails.Count -gt 0) {
    Write-Host ""
    Write-Host "FIXES NEEDED:" -ForegroundColor Red
    $fails | ForEach-Object {
        Write-Host "  [$($_.Area)] $($_.Check)" -ForegroundColor Red
        Write-Host "    → $($_.Fix)" -ForegroundColor Yellow
    }
}
