$resourceGroup  = "airg-platform-rg"
$uiAppName      = "tap"
$apiAppName     = "asp-tap-generator-api"
$uiClientId     = "ba9431f0-539e-48d9-9893-75a21716d6ae"
$apiClientId    = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$apiAppIdUri    = "api://$apiClientId"
$miObjectId     = "5906180b-d377-4856-aacf-1b09cba28655"
$sgObjectId     = "d7e09499-ac05-4053-b4d0-2f0f71822976"
$graphAppId     = "00000003-0000-0000-c000-000000000000"

$results = @()
function Check($area, $name, $pass, $actual, $fix) {
    $script:results += [PSCustomObject]@{
        Area   = $area
        Check  = $name
        Status = if ($pass) { "PASS" } else { "FAIL" }
        Actual = "$actual"
        Fix    = if ($pass) { "" } else { $fix }
    }
}

Write-Host ""
Write-Host "TAP Generator - Infrastructure Validation" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host "Logging in (az cli)..." -ForegroundColor Yellow
az login --use-device-code | Out-Null
$subId = (az account show | ConvertFrom-Json).id
Write-Host "Subscription: $subId" -ForegroundColor Gray

# ══════════════════════════════════════════════════════════════════════════════
# 1. UI APP SERVICE
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[1/5] UI App Service: $uiAppName" -ForegroundColor Cyan

$uiApp = az webapp show --name $uiAppName --resource-group $resourceGroup 2>$null | ConvertFrom-Json
Check "UI App Service" "Exists"        ($null -ne $uiApp) $(if ($uiApp) {"yes"} else {"not found"}) "Create UI App Service in portal"

if ($uiApp) {
    Check "UI App Service" "State = Running" ($uiApp.state -eq "Running") $uiApp.state "Portal -> App Service -> Start"
    Check "UI App Service" "HTTPS only"      ($uiApp.httpsOnly -eq $true)  $uiApp.httpsOnly "az webapp update --https-only true"

    # Easy Auth v2 via authsettingsV2 REST endpoint
    $authUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$uiAppName/config/authsettingsV2?api-version=2022-03-01"
    $authV2  = az rest --method GET --url $authUrl 2>$null | ConvertFrom-Json
    $ap      = $authV2.properties

    Check "UI Easy Auth" "Enabled"                    ($ap.platform.enabled -eq $true)                                          $ap.platform.enabled                                                               "run fix-easy-auth.ps1"
    Check "UI Easy Auth" "Unauthenticated = Redirect" ($ap.globalValidation.unauthenticatedClientAction -eq "RedirectToLoginPage") $ap.globalValidation.unauthenticatedClientAction                                  "run fix-easy-auth.ps1"
    Check "UI Easy Auth" "Token store ON"             ($ap.login.tokenStore.enabled -eq $true)                                   $ap.login.tokenStore.enabled                                                       "run fix-easy-auth.ps1"
    Check "UI Easy Auth" "Client ID = UI App Reg"     ($ap.identityProviders.azureActiveDirectory.registration.clientId -eq $uiClientId) $ap.identityProviders.azureActiveDirectory.registration.clientId          "run fix-easy-auth.ps1"
    Check "UI Easy Auth" "Issuer = v2 endpoint"       ($ap.identityProviders.azureActiveDirectory.registration.openIdIssuer -like "*v2.0*") $ap.identityProviders.azureActiveDirectory.registration.openIdIssuer   "run fix-easy-auth.ps1"
    $scopeParam = ($ap.identityProviders.azureActiveDirectory.login.loginParameters + $ap.login.loginParameters) -join " "
    Check "UI Easy Auth" "Scope includes access_as_user" ($scopeParam -like "*access_as_user*") $scopeParam "run fix-easy-auth.ps1"
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. API APP SERVICE
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "[2/5] API App Service: $apiAppName" -ForegroundColor Cyan

$apiApp = az webapp show --name $apiAppName --resource-group $resourceGroup 2>$null | ConvertFrom-Json
Check "API App Service" "Exists" ($null -ne $apiApp) $(if ($apiApp) {"yes"} else {"not found"}) "Create API App Service"

if ($apiApp) {
    Check "API App Service" "State = Running"           ($apiApp.state -eq "Running")      $apiApp.state          "Portal -> App Service -> Start"
    Check "API App Service" "HTTPS only"                ($apiApp.httpsOnly -eq $true)       $apiApp.httpsOnly      "az webapp update --https-only true"
    Check "API App Service" "System-assigned MI enabled" ($apiApp.identity.type -like "*SystemAssigned*") $apiApp.identity.type "Portal -> Identity -> System assigned -> ON"
    Check "API App Service" "MI principalId matches"    ($apiApp.identity.principalId -eq $miObjectId)   $apiApp.identity.principalId "Update miObjectId in azure-config.yaml"

    $settings    = az webapp config appsettings list --name $apiAppName --resource-group $resourceGroup 2>$null | ConvertFrom-Json
    $settingsMap = @{}; $settings | ForEach-Object { $settingsMap[$_.name] = $_.value }
    Check "API App Settings" "AzureAd__TenantId set"   (-not [string]::IsNullOrEmpty($settingsMap["AzureAd__TenantId"]))   $settingsMap["AzureAd__TenantId"]   "Deploy or set manually in portal"
    Check "API App Settings" "AzureAd__Audience set"   (-not [string]::IsNullOrEmpty($settingsMap["AzureAd__Audience"]))   $settingsMap["AzureAd__Audience"]   "Deploy or set manually in portal"
    Check "API App Settings" "ASPNETCORE_ENVIRONMENT"  ($settingsMap["ASPNETCORE_ENVIRONMENT"] -eq "Production") $settingsMap["ASPNETCORE_ENVIRONMENT"] "Set in portal app settings"
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. MANAGED IDENTITY GRAPH PERMISSIONS (az rest via Graph API)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "[3/5] Managed Identity Graph Permissions" -ForegroundColor Cyan

$graphSpJson = az rest --method GET `
    --url "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$graphAppId'&`$select=id,appRoles" 2>$null | ConvertFrom-Json
$graphSp = $graphSpJson.value | Select-Object -First 1

$assignmentsJson = az rest --method GET `
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$miObjectId/appRoleAssignments" 2>$null | ConvertFrom-Json
$assignments = $assignmentsJson.value

foreach ($perm in @("UserAuthenticationMethod.ReadWrite.All", "User.Read.All")) {
    $role     = $graphSp.appRoles | Where-Object { $_.value -eq $perm }
    $assigned = $assignments    | Where-Object { $_.appRoleId -eq $role.id }
    Check "MI Permissions" $perm ($null -ne $assigned) $(if ($assigned) {"assigned"} else {"missing"}) "run assign-mi-permissions.ps1"
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. ENTRA APP REGISTRATIONS (az cli / az rest)
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "[4/5] Entra App Registrations" -ForegroundColor Cyan

# UI App Registration
$uiAppReg = az ad app show --id $uiClientId 2>$null | ConvertFrom-Json
Check "UI App Reg" "Exists" ($null -ne $uiAppReg) $(if ($uiAppReg) {"yes"} else {"not found"}) "Create in Entra -> App Registrations"

if ($uiAppReg) {
    $tapRole = $uiAppReg.appRoles | Where-Object { $_.value -eq "TAP.Generator" -and $_.isEnabled }
    Check "UI App Reg" "TAP.Generator app role defined" ($null -ne $tapRole) $(if ($tapRole) {"yes"} else {"missing"}) "Add app role in Entra"

    $allRedirects = (($uiAppReg.web.redirectUris + $uiAppReg.spa.redirectUris) | Where-Object { $_ }) -join ","
    Check "UI App Reg" "Redirect URI registered" ($allRedirects -like "*azurewebsites.net*") $allRedirects "Add redirect URI in Entra -> Authentication"

    $tokenVersion = $uiAppReg.api.requestedAccessTokenVersion
    Check "UI App Reg" "accessTokenAcceptedVersion = 2" ($tokenVersion -eq 2) $tokenVersion "run fix-ui-appreg-tokenversion.ps1"
}

# API App Registration
$apiAppReg = az ad app show --id $apiClientId 2>$null | ConvertFrom-Json
Check "API App Reg" "Exists" ($null -ne $apiAppReg) $(if ($apiAppReg) {"yes"} else {"not found"}) "Create in Entra -> App Registrations"

if ($apiAppReg) {
    $scopeDefined = $apiAppReg.api.oauth2PermissionScopes | Where-Object { $_.value -eq "access_as_user" -and $_.isEnabled }
    Check "API App Reg" "access_as_user scope defined" ($null -ne $scopeDefined) $(if ($scopeDefined) {"yes"} else {"missing"}) "Entra -> TAP Generator API -> Expose an API -> Add scope"

    $appIdUriOk = $apiAppReg.identifierUris -contains $apiAppIdUri
    Check "API App Reg" "App ID URI = api://<clientId>" $appIdUriOk ($apiAppReg.identifierUris -join ",") "Entra -> Expose an API -> Set Application ID URI"

    $tokenVersion = $apiAppReg.api.requestedAccessTokenVersion
    Check "API App Reg" "accessTokenAcceptedVersion = 2" ($tokenVersion -eq 2) $tokenVersion "Set requestedAccessTokenVersion=2 in manifest"
}

# UI App Reg - admin consent for access_as_user
$uiSpJson = az ad sp show --id $uiClientId 2>$null | ConvertFrom-Json
if ($uiSpJson) {
    $grants = az rest --method GET `
        --url "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($uiSpJson.id)'" 2>$null | ConvertFrom-Json
    $hasConsent = $grants.value | Where-Object { $_.scope -like "*access_as_user*" }
    Check "UI App Reg" "access_as_user admin consent granted" ($null -ne $hasConsent) $(if ($hasConsent) {"granted"} else {"missing"}) "Entra -> TAP Generator UI -> API Permissions -> Grant admin consent"
}

# Security Group role assignment
if ($uiSpJson) {
    $roleAssignments = az rest --method GET `
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/$($uiSpJson.id)/appRoleAssignedTo" 2>$null | ConvertFrom-Json
    $sgAssigned = $roleAssignments.value | Where-Object { $_.principalId -eq $sgObjectId }
    Check "Entra Group" "SG assigned TAP.Generator role" ($null -ne $sgAssigned) $(if ($sgAssigned) {"assigned"} else {"missing"}) "Entra -> Enterprise Apps -> TAP Generator UI -> Users and groups -> Add group"
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. APIM
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "[5/5] APIM" -ForegroundColor Cyan

$apimList = az apim list --resource-group $resourceGroup 2>$null | ConvertFrom-Json
$apim     = $apimList | Select-Object -First 1
Check "APIM" "Instance exists in resource group" ($null -ne $apim) $(if ($apim) {$apim.name} else {"not found"}) "Create APIM in portal"

if ($apim) {
    Check "APIM" "Provisioning state = Succeeded" ($apim.provisioningState -eq "Succeeded") $apim.provisioningState "Wait for provisioning"
    Write-Host "  APIM Gateway URL: $($apim.gatewayUrl)" -ForegroundColor Gray

    $apiCheck = az apim api show --service-name $apim.name --resource-group $resourceGroup --api-id "tap-generator" 2>$null | ConvertFrom-Json
    Check "APIM" "tap-generator API exists" ($null -ne $apiCheck) $(if ($apiCheck) {"yes"} else {"not found"}) "Re-run create-apim.ps1 step 2"

    if ($apiCheck) {
        $policyUrl  = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$($apim.name)/apis/tap-generator/policies/policy?api-version=2022-08-01"
        $policyRaw  = az rest --method GET --url $policyUrl 2>$null
        $policy     = $policyRaw | ConvertFrom-Json 2>$null
        $policyLen  = if ($policy.properties.value) { $policy.properties.value.Length } elseif ($policyRaw -and $policyRaw.Length -gt 50) { $policyRaw.Length } else { 0 }
        Check "APIM" "Policy applied" ($policyLen -gt 50 -or ($null -ne $policy -and $null -ne $policy.id)) "$policyLen chars / id=$($policy.id)" "Apply policy via portal"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# RESULTS
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "VALIDATION RESULTS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
$results | Format-Table Area, Check, Status, Actual -AutoSize

$failures = $results | Where-Object { $_.Status -eq "FAIL" }
$passes   = $results | Where-Object { $_.Status -eq "PASS" }
Write-Host "PASS: $($passes.Count)   FAIL: $($failures.Count)" -ForegroundColor $(if ($failures.Count -eq 0) {"Green"} else {"Yellow"})

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILURES TO FIX:" -ForegroundColor Red
    $failures | ForEach-Object {
        Write-Host "  [$($_.Area)] $($_.Check)" -ForegroundColor Red
        Write-Host "    Fix: $($_.Fix)" -ForegroundColor Yellow
    }
}
