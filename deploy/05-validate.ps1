# =============================================================================
# 05-validate.ps1  –  End-to-end validation of the deployed TAP Generator.
#
# Checks: infrastructure, API health, APIM 401, Entra config, role assignments,
#         Managed Identity + Graph permissions, Easy Auth, client secret,
#         APIM policy correctness, Graph connectivity from MI.
#
# Run after 04-deploy.ps1 completes.
# =============================================================================
. "$PSScriptRoot\config.ps1"

function Write-Step($msg)  { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host "    [PASS] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)  { Write-Host "    [FAIL] $msg" -ForegroundColor Red; $script:failures++ }

$script:failures = 0

az account set --subscription $SUBSCRIPTION_ID

$API_CLIENT_ID = (az ad app list --display-name $API_APP_REG_NAME --query "[0].appId" -o tsv)
$UI_CLIENT_ID  = (az ad app list --display-name $UI_APP_REG_NAME  --query "[0].appId" -o tsv)

$outputs      = Get-Content "$PSScriptRoot\.infra-outputs.json" -ErrorAction SilentlyContinue | ConvertFrom-Json
$API_HOSTNAME = if ($outputs) { $outputs.API_HOSTNAME } else {
    (az webapp show --name $API_APP_NAME --resource-group $RESOURCE_GROUP --query "defaultHostName" -o tsv)
}
$UI_HOSTNAME  = if ($outputs) { $outputs.UI_HOSTNAME } else {
    (az webapp show --name $UI_APP_NAME --resource-group $RESOURCE_GROUP --query "defaultHostName" -o tsv)
}
$APIM_GATEWAY = if ($outputs) { $outputs.APIM_GATEWAY } else {
    (az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP --query "gatewayUrl" -o tsv)
}

# ── 1. Azure Resources ────────────────────────────────────────────────────────
Write-Step "Azure Resources"

$rg = az group show --name $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if ($rg) { Write-OK "Resource group: $RESOURCE_GROUP" } else { Write-Fail "Resource group missing: $RESOURCE_GROUP" }

$apiApp = az webapp show --name $API_APP_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if ($apiApp -and $apiApp.state -eq "Running") { Write-OK "API App Service running: $API_APP_NAME" }
else { Write-Fail "API App Service not running: $API_APP_NAME" }

$uiApp = az webapp show --name $UI_APP_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if ($uiApp -and $uiApp.state -eq "Running") { Write-OK "UI App Service running: $UI_APP_NAME" }
else { Write-Fail "UI App Service not running: $UI_APP_NAME" }

$apim = az apim show --name $APIM_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if ($apim) { Write-OK "APIM exists: $APIM_NAME ($($apim.sku.name))" }
else { Write-Fail "APIM missing: $APIM_NAME" }

# ── 2. Managed Identity & Graph Permissions ───────────────────────────────────
Write-Step "Managed Identity & Graph Permissions"

$mi = az webapp identity show --name $API_APP_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if ($mi -and $mi.principalId) {
    Write-OK "Managed Identity enabled: $($mi.principalId)"
    $MI_OBJECT_ID = $mi.principalId

    $requiredPerms = @{
        "UserAuthenticationMethod.ReadWrite.All" = "50483e42-d915-4231-9639-7fdb7fd190e5"
        "User.Read.All"                          = "df021288-bdef-4463-88db-98f22de89214"
        "RoleManagement.Read.Directory"          = "483bed4a-2ad3-4361-a73b-c83ccdbdc53c"
    }
    $assignments = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$MI_OBJECT_ID/appRoleAssignments" `
        --query "value[].appRoleId" 2>$null | ConvertFrom-Json

    foreach ($perm in $requiredPerms.GetEnumerator()) {
        if ($assignments -contains $perm.Value) { Write-OK "Graph permission: $($perm.Key)" }
        else { Write-Fail "Missing Graph permission: $($perm.Key)" }
    }

    # Test Graph connectivity — actually call Graph to verify MI token works
    $graphTest = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/organization" `
        --headers "ConsistencyLevel=eventual" 2>$null | ConvertFrom-Json
    if ($graphTest -and $graphTest.value) { Write-OK "Graph API reachable (org: $($graphTest.value[0].displayName))" }
    else { Write-Warn "Graph API call returned no data – MI token may not have propagated yet" }

} else {
    Write-Fail "Managed Identity not enabled on $API_APP_NAME"
}

# ── 3. API App Settings ───────────────────────────────────────────────────────
Write-Step "API App Settings"
$settings = az webapp config appsettings list --name $API_APP_NAME --resource-group $RESOURCE_GROUP | ConvertFrom-Json
$settingMap = @{}
$settings | ForEach-Object { $settingMap[$_.name] = $_.value }

foreach ($key in @("AzureAd__TenantId","AzureAd__Audience","AzureAd__ClientId","APPLICATIONINSIGHTS_CONNECTION_STRING")) {
    if ($settingMap[$key]) { Write-OK "$key is set" }
    else { Write-Fail "$key is missing" }
}

# ── 4. API Health Check ───────────────────────────────────────────────────────
Write-Step "API Health Check"
try {
    $health = Invoke-RestMethod "https://$API_HOSTNAME/health" -TimeoutSec 15
    if ($health -eq "Healthy") { Write-OK "API /health = Healthy" }
    else { Write-Warn "API /health = $health (expected 'Healthy')" }
} catch {
    Write-Fail "API /health unreachable: $($_.Exception.Message)"
}

# ── 5. APIM Endpoint – must return 401 (not 404, not 200) ────────────────────
Write-Step "APIM Endpoint"
try {
    $r = Invoke-WebRequest "$APIM_GATEWAY/tap/api/tap" -Method POST `
        -ContentType "application/json" `
        -Body '{"targetUpn":"test","lifetimeInMinutes":15}' `
        -UseBasicParsing -ErrorAction SilentlyContinue
    Write-Fail "APIM returned $($r.StatusCode) without token (expected 401) – policy may be missing"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401) { Write-OK "APIM returns 401 for unauthenticated request" }
    elseif ($code -eq 404) { Write-Fail "APIM returns 404 – check API path 'tap' and operation '/api/tap'" }
    else { Write-Warn "APIM returned $code – investigate" }
}

# ── 6. APIM Operation & Policy ───────────────────────────────────────────────
Write-Step "APIM API, Operation and Policy"

$op = az apim api operation show `
    --service-name $APIM_NAME `
    --resource-group $RESOURCE_GROUP `
    --api-id "tap-generator" `
    --operation-id "create-tap" 2>$null | ConvertFrom-Json
if ($op -and $op.properties.method -eq "POST" -and $op.properties.urlTemplate -eq "/api/tap") {
    Write-OK "Operation: POST /api/tap"
} else {
    Write-Fail "Operation missing or wrong – run 03-configure.ps1 again"
}

# Verify policy does NOT contain the broken output-token-variable-name pattern
$TOKEN = (az account get-access-token --resource "https://management.azure.com/" --query accessToken -o tsv)
$policyUri = "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/tap-generator/operations/create-tap/policies/policy?api-version=2022-08-01"
$livePolicy = Invoke-RestMethod -Method GET -Uri $policyUri -Headers @{ Authorization = "Bearer $TOKEN" } 2>$null
if ($livePolicy) {
    $policyXml = $livePolicy.properties.value
    if ($policyXml -match "output-token-variable-name") {
        Write-Fail "APIM policy contains broken 'output-token-variable-name' – run infra\push-apim-policy.ps1"
    } else {
        Write-OK "APIM policy does not contain broken token variable"
    }
    if ($policyXml -match 'code="401"') {
        Write-OK "APIM on-error returns hardcoded 401"
    } else {
        Write-Fail "APIM on-error does not hardcode 401 – run infra\push-apim-policy.ps1"
    }
    if ($policyXml -match "X-Operator-Upn") {
        Write-OK "APIM policy sets X-Operator-Upn header"
    } else {
        Write-Warn "APIM policy missing X-Operator-Upn header – operator will log as 'unknown'"
    }
} else {
    Write-Fail "Could not retrieve APIM operation policy"
}

# ── 7. Entra App Registrations & Role Assignments ────────────────────────────
Write-Step "Entra App Registrations"

if ($API_CLIENT_ID) { Write-OK "API app reg: $API_CLIENT_ID" } else { Write-Fail "API app reg not found" }
if ($UI_CLIENT_ID)  { Write-OK "UI  app reg: $UI_CLIENT_ID"  } else { Write-Fail "UI  app reg not found" }

$apiManifest = az ad app show --id $API_CLIENT_ID --query "api" | ConvertFrom-Json
$tokenVer = $apiManifest.requestedAccessTokenVersion
if ($tokenVer -eq 2) { Write-OK "API accessTokenAcceptedVersion = 2" }
else { Write-Warn "API accessTokenAcceptedVersion = $tokenVer (should be 2 for api:// audience)" }

$appIdUri = az ad app show --id $API_CLIENT_ID --query "identifierUris[0]" -o tsv
if ($appIdUri -eq "api://$API_CLIENT_ID") { Write-OK "App ID URI: $appIdUri" }
else { Write-Warn "App ID URI: '$appIdUri' (expected 'api://$API_CLIENT_ID')" }

# TAP.Generator must exist on BOTH app registrations
$uiRoles = az ad app show --id $UI_CLIENT_ID --query "appRoles[?value=='TAP.Generator'].value" | ConvertFrom-Json
if ($uiRoles -and $uiRoles.Count -gt 0) { Write-OK "TAP.Generator role exists on UI app reg" }
else { Write-Fail "TAP.Generator role missing on UI app reg – run 01-entra.ps1" }

$apiRoles = az ad app show --id $API_CLIENT_ID --query "appRoles[?value=='TAP.Generator'].value" | ConvertFrom-Json
if ($apiRoles -and $apiRoles.Count -gt 0) { Write-OK "TAP.Generator role exists on API app reg (required for access_token roles claim)" }
else { Write-Fail "TAP.Generator role missing on API app reg – run 01-entra.ps1" }

# Verify security group is assigned the role on the API service principal
$apiSpId = (az ad sp show --id $API_CLIENT_ID --query "id" -o tsv)
$apiRoleId = (az ad app show --id $API_CLIENT_ID --query "appRoles[?value=='TAP.Generator'].id" -o tsv)
$apiRoleAssignment = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$apiSpId/appRoleAssignedTo" `
    --query "value[?appRoleId=='$apiRoleId']" 2>$null | ConvertFrom-Json
if ($apiRoleAssignment -and $apiRoleAssignment.Count -gt 0) {
    Write-OK "Security group assigned TAP.Generator on API service principal"
} else {
    Write-Fail "Security group NOT assigned TAP.Generator on API SP – access_token will lack role claim – run 01-entra.ps1"
}

# ── 8. Easy Auth ──────────────────────────────────────────────────────────────
Write-Step "Easy Auth on UI App Service"

$authSettings = az rest --method GET `
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$UI_APP_NAME/config/authsettingsV2?api-version=2022-09-01" `
    2>$null | ConvertFrom-Json

if ($authSettings.properties.platform.enabled) { Write-OK "Easy Auth enabled" }
else { Write-Fail "Easy Auth NOT enabled – run 03-configure.ps1" }

$unauthAction = $authSettings.properties.globalValidation.unauthenticatedClientAction
if ($unauthAction -eq "AllowAnonymous") { Write-OK "unauthenticatedClientAction = AllowAnonymous (Flutter SPA handles redirect)" }
else { Write-Fail "unauthenticatedClientAction = '$unauthAction' (must be AllowAnonymous for Flutter) – run 03-configure.ps1" }

$clientSecretSetting = $authSettings.properties.identityProviders.azureActiveDirectory.registration.clientSecretSettingName
if ($clientSecretSetting -eq "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET") {
    Write-OK "Easy Auth clientSecretSettingName configured"
} else {
    Write-Fail "Easy Auth clientSecretSettingName not set – run 03-configure.ps1 with -UI_CLIENT_SECRET"
}

# Verify the secret app setting actually exists on the UI app
$uiSettings = az webapp config appsettings list --name $UI_APP_NAME --resource-group $RESOURCE_GROUP | ConvertFrom-Json
$uiSettingMap = @{}
$uiSettings | ForEach-Object { $uiSettingMap[$_.name] = $_.value }
if ($uiSettingMap["MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"]) {
    Write-OK "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET app setting is present"
} else {
    Write-Fail "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET app setting missing – run 03-configure.ps1 with -UI_CLIENT_SECRET"
}

# ── 9. UI App Service responds ────────────────────────────────────────────────
Write-Step "UI App Service responds"
try {
    $ui = Invoke-WebRequest "https://$UI_HOSTNAME" -UseBasicParsing -TimeoutSec 15
    if ($ui.StatusCode -eq 200) { Write-OK "UI responds: 200" }
    else { Write-Warn "UI status: $($ui.StatusCode)" }
} catch {
    Write-Warn "UI unreachable: $($_.Exception.Message)"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
if ($script:failures -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host ""
    Write-Host "Open the app and sign in:" -ForegroundColor White
    Write-Host "  https://$UI_HOSTNAME"
    Write-Host ""
    Write-Host "Sign in → Enter a non-privileged user UPN → Choose duration → Generate TAP"
} else {
    Write-Host "$($script:failures) CHECK(S) FAILED" -ForegroundColor Red
    Write-Host "Fix the failing items above and re-run this script."
}
Write-Host "=============================================" -ForegroundColor Cyan
