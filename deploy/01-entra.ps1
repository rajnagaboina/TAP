# =============================================================================
# 01-entra.ps1  –  Create Entra ID app registrations, roles, scopes, group.
#
# Prerequisites:
#   - az cli logged in as a user with Application Administrator (or Global Admin)
#   - Run:  az login
#
# Run time: ~2 minutes
# Safe to re-run (checks before creating).
# =============================================================================
. "$PSScriptRoot\config.ps1"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    FAIL: $msg" -ForegroundColor Red; exit 1 }

az account set --subscription $SUBSCRIPTION_ID
Write-Host "Subscription: $SUBSCRIPTION_ID" -ForegroundColor Gray

# ── 1. API App Registration ───────────────────────────────────────────────────
Write-Step "API App Registration: $API_APP_REG_NAME"

$apiApp = az ad app list --display-name $API_APP_REG_NAME | ConvertFrom-Json
if ($apiApp.Count -eq 0) {
    $apiApp = az ad app create --display-name $API_APP_REG_NAME | ConvertFrom-Json
    Write-OK "Created: $($apiApp.appId)"
} else {
    $apiApp = $apiApp[0]
    Write-OK "Already exists: $($apiApp.appId)"
}
$API_CLIENT_ID = $apiApp.appId

# Set accessTokenAcceptedVersion = 2 (v2 tokens, audience = api://{clientId})
$manifest = @{ api = @{ requestedAccessTokenVersion = 2 } } | ConvertTo-Json -Compress
az ad app update --id $API_CLIENT_ID --set "api=$manifest" 2>$null
# Alternative approach for token version
az ad app update --id $API_CLIENT_ID `
    --set "api.requestedAccessTokenVersion=2" 2>$null | Out-Null
Write-OK "accessTokenAcceptedVersion = 2"

# Set App ID URI
$appIdUri = "api://$API_CLIENT_ID"
az ad app update --id $API_CLIENT_ID --identifier-uris $appIdUri 2>$null | Out-Null
Write-OK "App ID URI: $appIdUri"

# Add access_as_user scope
$existingScopes = az ad app show --id $API_CLIENT_ID --query "api.oauth2PermissionScopes" | ConvertFrom-Json
$scopeExists = $existingScopes | Where-Object { $_.value -eq "access_as_user" }
if (-not $scopeExists) {
    $scopeId = [guid]::NewGuid().ToString()
    $scopeJson = @{
        adminConsentDescription = "Allows the app to call the TAP Generator API on behalf of the signed-in user"
        adminConsentDisplayName = "Access TAP Generator API"
        id                      = $scopeId
        isEnabled               = $true
        type                    = "User"
        userConsentDescription  = "Allow this app to access TAP Generator API on your behalf"
        userConsentDisplayName  = "Access TAP Generator API"
        value                   = "access_as_user"
    }
    $apiPatch = @{ oauth2PermissionScopes = @($scopeJson) } | ConvertTo-Json -Depth 5 -Compress
    az ad app update --id $API_CLIENT_ID --set "api=$apiPatch" | Out-Null
    Write-OK "Scope access_as_user created (id: $scopeId)"
} else {
    Write-OK "Scope access_as_user already exists"
    $scopeId = $scopeExists.id
}

# Create service principal if missing
$apiSp = az ad sp show --id $API_CLIENT_ID 2>$null | ConvertFrom-Json
if (-not $apiSp) {
    az ad sp create --id $API_CLIENT_ID | Out-Null
    Write-OK "Service principal created"
} else {
    Write-OK "Service principal already exists"
}

# ── 2. UI App Registration ────────────────────────────────────────────────────
Write-Step "UI App Registration: $UI_APP_REG_NAME"

$uiApp = az ad app list --display-name $UI_APP_REG_NAME | ConvertFrom-Json
if ($uiApp.Count -eq 0) {
    $uiApp = az ad app create --display-name $UI_APP_REG_NAME --sign-in-audience "AzureADMyOrg" | ConvertFrom-Json
    Write-OK "Created: $($uiApp.appId)"
} else {
    $uiApp = $uiApp[0]
    Write-OK "Already exists: $($uiApp.appId)"
}
$UI_CLIENT_ID = $uiApp.appId

# Add TAP.Generator app role
$existingRoles = az ad app show --id $UI_CLIENT_ID --query "appRoles" | ConvertFrom-Json
$roleExists = $existingRoles | Where-Object { $_.value -eq "TAP.Generator" }
if (-not $roleExists) {
    $roleId = [guid]::NewGuid().ToString()
    $roleJson = @{
        allowedMemberTypes = @("User")
        description        = "Grants permission to generate TAPs for non-privileged users"
        displayName        = "TAP Generator Operator"
        id                 = $roleId
        isEnabled          = $true
        value              = "TAP.Generator"
    }
    $rolesPatch = @($roleJson) | ConvertTo-Json -Depth 5 -Compress
    az ad app update --id $UI_CLIENT_ID --app-roles $rolesPatch | Out-Null
    Write-OK "App role TAP.Generator created (id: $roleId)"
} else {
    Write-OK "App role TAP.Generator already exists"
    $roleId = $roleExists.id
}

# Add required API permissions (openid, profile, email + access_as_user)
$requiredAccess = @(
    @{
        resourceAppId  = "00000003-0000-0000-c000-000000000000"  # MS Graph
        resourceAccess = @(
            @{ id = "37f7f235-527c-4136-accd-4a02d197296e"; type = "Scope" }  # openid
            @{ id = "14dad69e-099b-42c9-810b-d002981feec1"; type = "Scope" }  # profile
            @{ id = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"; type = "Scope" }  # email
        )
    },
    @{
        resourceAppId  = $API_CLIENT_ID
        resourceAccess = @(
            @{ id = $scopeId; type = "Scope" }  # access_as_user
        )
    }
) | ConvertTo-Json -Depth 10 -Compress

az ad app update --id $UI_CLIENT_ID --required-resource-accesses $requiredAccess | Out-Null
Write-OK "API permissions configured"

# Create service principal for UI app
$uiSp = az ad sp show --id $UI_CLIENT_ID 2>$null | ConvertFrom-Json
if (-not $uiSp) {
    $uiSp = az ad sp create --id $UI_CLIENT_ID | ConvertFrom-Json
    Write-OK "UI service principal created"
} else {
    Write-OK "UI service principal already exists"
}

# ── 3. Security group ─────────────────────────────────────────────────────────
Write-Step "Security Group: $OPERATORS_GROUP"

$group = az ad group list --display-name $OPERATORS_GROUP | ConvertFrom-Json
if ($group.Count -eq 0) {
    $group = az ad group create `
        --display-name $OPERATORS_GROUP `
        --mail-nickname "SG-IAM-TAP-Generators" | ConvertFrom-Json
    Write-OK "Created group: $($group.id)"
} else {
    $group = $group[0]
    Write-OK "Already exists: $($group.id)"
}
$GROUP_OBJECT_ID = $group.id

# Assign TAP.Generator role to the group via Enterprise App (UI service principal)
$uiSpId = $uiSp.id
$existing = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$uiSpId/appRoleAssignedTo" `
    --query "value[?appRoleId=='$roleId']" 2>$null | ConvertFrom-Json
if (-not $existing -or $existing.Count -eq 0) {
    az rest --method POST `
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$uiSpId/appRoleAssignedTo" `
        --body "{`"principalId`":`"$GROUP_OBJECT_ID`",`"resourceId`":`"$uiSpId`",`"appRoleId`":`"$roleId`"}" | Out-Null
    Write-OK "TAP.Generator role assigned to $OPERATORS_GROUP"
} else {
    Write-OK "Role assignment already exists"
}

# ── 4. Admin consent ──────────────────────────────────────────────────────────
Write-Step "Granting admin consent for UI app permissions"
az ad app permission admin-consent --id $UI_CLIENT_ID 2>$null | Out-Null
Write-OK "Admin consent granted (or already granted)"

# ── Output ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "ENTRA SETUP COMPLETE" -ForegroundColor Green
Write-Host "  API_CLIENT_ID  = $API_CLIENT_ID"
Write-Host "  UI_CLIENT_ID   = $UI_CLIENT_ID"
Write-Host "  GROUP_OBJECT_ID= $GROUP_OBJECT_ID"
Write-Host "  App Role ID    = $roleId"
Write-Host "  Scope ID       = $scopeId"
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Copy API_CLIENT_ID and UI_CLIENT_ID into deploy\config.ps1 if they are new"
Write-Host "  2. Add yourself (or test user) to the '$OPERATORS_GROUP' group in Entra"
Write-Host "  3. Run: .\deploy\02-azure.ps1"
