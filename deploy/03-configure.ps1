# =============================================================================
# 03-configure.ps1  –  Configure App Services, Managed Identity, Easy Auth,
#                      Graph permissions, APIM policies, GitHub variables.
#
# Prerequisites:
#   - 01-entra.ps1 and 02-azure.ps1 completed
#   - az cli + gh cli logged in
#   - gh auth login  (GitHub CLI)
#
# Run time: ~3 minutes
# Safe to re-run.
# =============================================================================
. "$PSScriptRoot\config.ps1"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    FAIL: $msg" -ForegroundColor Red; exit 1 }

az account set --subscription $SUBSCRIPTION_ID

# Load outputs from script 02
$outputs = Get-Content "$PSScriptRoot\.infra-outputs.json" | ConvertFrom-Json
$API_HOSTNAME = $outputs.API_HOSTNAME
$UI_HOSTNAME  = $outputs.UI_HOSTNAME
$APIM_GATEWAY = $outputs.APIM_GATEWAY
$AI_CONN_STR  = $outputs.AI_CONN_STR

# Load Entra IDs
$API_CLIENT_ID = (az ad app list --display-name $API_APP_REG_NAME --query "[0].appId" -o tsv)
$UI_CLIENT_ID  = (az ad app list --display-name $UI_APP_REG_NAME  --query "[0].appId" -o tsv)

if (-not $API_CLIENT_ID) { Write-Fail "API App Registration not found. Run 01-entra.ps1 first." }
if (-not $UI_CLIENT_ID)  { Write-Fail "UI App Registration not found. Run 01-entra.ps1 first." }

Write-Host "API_CLIENT_ID : $API_CLIENT_ID" -ForegroundColor Gray
Write-Host "UI_CLIENT_ID  : $UI_CLIENT_ID"  -ForegroundColor Gray
Write-Host "API Hostname  : $API_HOSTNAME"  -ForegroundColor Gray
Write-Host "UI  Hostname  : $UI_HOSTNAME"   -ForegroundColor Gray

# ── 1. API App Service – Managed Identity ────────────────────────────────────
Write-Step "Enabling Managed Identity on API App Service"
$mi = az webapp identity assign `
    --name $API_APP_NAME `
    --resource-group $RESOURCE_GROUP | ConvertFrom-Json
$MI_OBJECT_ID = $mi.principalId
Write-OK "MI Object ID: $MI_OBJECT_ID"

# ── 2. API App Service – App Settings ────────────────────────────────────────
Write-Step "Configuring API App Settings"
az webapp config appsettings set `
    --name $API_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings `
        "AzureAd__TenantId=$TENANT_ID" `
        "AzureAd__Audience=api://$API_CLIENT_ID" `
        "AzureAd__ClientId=$API_CLIENT_ID" `
        "AzureAd__Instance=https://login.microsoftonline.com/" `
        "APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONN_STR" `
        "ASPNETCORE_ENVIRONMENT=Production" `
        "WEBSITE_RUN_FROM_PACKAGE=1" | Out-Null
Write-OK "App settings applied"

# ── 3. Grant Managed Identity Graph permissions ───────────────────────────────
Write-Step "Granting Graph permissions to Managed Identity"

$graphSpId = (az ad sp show --id "00000003-0000-0000-c000-000000000000" --query "id" -o tsv)

$permissions = @(
    @{ name = "UserAuthenticationMethod.ReadWrite.All"; id = "50483e42-d915-4231-9639-7fdb7fd190e5" },
    @{ name = "User.Read.All";                         id = "df021288-bdef-4463-88db-98f22de89214" },
    @{ name = "RoleManagement.Read.Directory";         id = "483bed4a-2ad3-4361-a73b-c83ccdbdc53c" }
)

foreach ($perm in $permissions) {
    $existing = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$MI_OBJECT_ID/appRoleAssignments" `
        --query "value[?appRoleId=='$($perm.id)']" 2>$null | ConvertFrom-Json
    if (-not $existing -or $existing.Count -eq 0) {
        az rest --method POST `
            --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$MI_OBJECT_ID/appRoleAssignments" `
            --body "{`"principalId`":`"$MI_OBJECT_ID`",`"resourceId`":`"$graphSpId`",`"appRoleId`":`"$($perm.id)`"}" | Out-Null
        Write-OK "Granted: $($perm.name)"
    } else {
        Write-OK "Already granted: $($perm.name)"
    }
}

# ── 4. UI App Service – Easy Auth ────────────────────────────────────────────
Write-Step "Configuring Easy Auth on UI App Service"

$redirectUri = "https://$UI_HOSTNAME/.auth/login/aad/callback"

# Add redirect URI to UI app registration
$existingUris = az ad app show --id $UI_CLIENT_ID --query "web.redirectUris" | ConvertFrom-Json
if ($existingUris -notcontains $redirectUri) {
    $allUris = @($existingUris) + $redirectUri
    $urisJson = $allUris | ConvertTo-Json -Compress
    az ad app update --id $UI_CLIENT_ID --web-redirect-uris $allUris | Out-Null
    Write-OK "Redirect URI added: $redirectUri"
} else {
    Write-OK "Redirect URI already present"
}

# Configure Easy Auth V2
$easyAuthConfig = @{
    platform = @{ enabled = $true }
    globalValidation = @{
        requireAuthentication     = $true
        unauthenticatedClientAction = "RedirectToLoginPage"
    }
    identityProviders = @{
        azureActiveDirectory = @{
            enabled = $true
            registration = @{
                clientId             = $UI_CLIENT_ID
                openIdIssuer         = "https://login.microsoftonline.com/$TENANT_ID/v2.0"
            }
            login = @{
                loginParameters = @(
                    "scope=openid profile email offline_access api://$API_CLIENT_ID/access_as_user"
                )
            }
            validation = @{
                allowedAudiences = @($UI_CLIENT_ID)
            }
        }
    }
    login = @{
        tokenStore = @{ enabled = $true }
    }
} | ConvertTo-Json -Depth 10 -Compress

$easyAuthBody = @{ properties = ($easyAuthConfig | ConvertFrom-Json) } | ConvertTo-Json -Depth 15 -Compress

az rest --method PUT `
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$UI_APP_NAME/config/authsettingsV2?api-version=2022-09-01" `
    --body $easyAuthBody | Out-Null
Write-OK "Easy Auth configured on $UI_APP_NAME"

# ── 5. APIM – API + Operation + Policies ─────────────────────────────────────
Write-Step "Configuring APIM API and policy"

$apiBackendUrl = "https://$API_HOSTNAME"
$uiOrigin      = "https://$UI_HOSTNAME"

# Create API
$apiExists = az apim api show `
    --service-name $APIM_NAME `
    --resource-group $RESOURCE_GROUP `
    --api-id "tap-generator" 2>$null | ConvertFrom-Json
if (-not $apiExists) {
    az apim api create `
        --service-name $APIM_NAME `
        --resource-group $RESOURCE_GROUP `
        --api-id "tap-generator" `
        --path "tap" `
        --display-name "TAP Generator API" `
        --protocols https `
        --service-url $apiBackendUrl | Out-Null
    Write-OK "APIM API created"
} else {
    Write-OK "APIM API already exists"
}

# Create operation
$opExists = az apim api operation show `
    --service-name $APIM_NAME `
    --resource-group $RESOURCE_GROUP `
    --api-id "tap-generator" `
    --operation-id "create-tap" 2>$null | ConvertFrom-Json
if (-not $opExists) {
    az apim api operation create `
        --service-name $APIM_NAME `
        --resource-group $RESOURCE_GROUP `
        --api-id "tap-generator" `
        --operation-id "create-tap" `
        --display-name "Generate TAP" `
        --method POST `
        --url-template "/api/tap" | Out-Null
    Write-OK "APIM operation created"
} else {
    Write-OK "APIM operation already exists"
}

# Apply API-level CORS policy
$corsPolicy = @"
<policies>
  <inbound>
    <cors allow-credentials="true">
      <allowed-origins>
        <origin>$uiOrigin</origin>
      </allowed-origins>
      <allowed-methods preflight-result-max-age="300">
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Authorization</header>
        <header>Content-Type</header>
      </allowed-headers>
      <expose-headers>
        <header>X-Request-Id</header>
      </expose-headers>
    </cors>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
"@

# Apply operation-level JWT+routing policy
$operationPolicy = @"
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization"
                  failed-validation-httpcode="401"
                  failed-validation-error-message="Unauthorized: valid Bearer token with TAP.Generator role required."
                  require-expiration-time="true"
                  require-signed-tokens="true">
      <openid-config url="https://login.microsoftonline.com/$TENANT_ID/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>$API_CLIENT_ID</audience>
        <audience>api://$API_CLIENT_ID</audience>
      </audiences>
      <issuers>
        <issuer>https://login.microsoftonline.com/$TENANT_ID/v2.0</issuer>
        <issuer>https://sts.windows.net/$TENANT_ID/</issuer>
      </issuers>
      <required-claims>
        <claim name="roles" match="any" separator=" ">
          <value>TAP.Generator</value>
        </claim>
      </required-claims>
    </validate-jwt>
    <set-backend-service base-url="$apiBackendUrl" />
    <set-header name="X-Operator-Upn" exists-action="override">
      <value>@(context.Request.Headers.GetValueOrDefault("X-MS-CLIENT-PRINCIPAL-NAME", context.User?.Email ?? "unknown"))</value>
    </set-header>
    <set-header name="X-Request-Id" exists-action="skip">
      <value>@(Guid.NewGuid().ToString())</value>
    </set-header>
  </inbound>
  <backend><base /></backend>
  <outbound>
    <base />
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="X-AspNet-Version" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />
  </outbound>
  <on-error>
    <base />
    <set-header name="Access-Control-Allow-Origin" exists-action="override">
      <value>$uiOrigin</value>
    </set-header>
    <set-header name="Access-Control-Allow-Credentials" exists-action="override">
      <value>true</value>
    </set-header>
    <return-response>
      <set-status code="401" reason="Unauthorized" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>{"error": "Unauthorized: valid token with TAP.Generator role required."}</set-body>
    </return-response>
  </on-error>
</policies>
"@

# Push API-level policy via REST (az cli doesn't support API-level policy well)
$subId = $SUBSCRIPTION_ID
$TOKEN = (az account get-access-token --resource "https://management.azure.com/" --query accessToken -o tsv)

$corsPayload   = @{ properties = @{ format = "rawxml"; value = $corsPolicy      } } | ConvertTo-Json -Depth 5
$opPayload     = @{ properties = @{ format = "rawxml"; value = $operationPolicy } } | ConvertTo-Json -Depth 5

$base = "https://management.azure.com/subscriptions/$subId/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME"

Invoke-RestMethod -Method PUT `
    -Uri "$base/apis/tap-generator/policies/policy?api-version=2022-08-01" `
    -Headers @{ Authorization = "Bearer $TOKEN" } `
    -ContentType "application/json" `
    -Body $corsPayload | Out-Null
Write-OK "APIM API-level (CORS) policy applied"

Invoke-RestMethod -Method PUT `
    -Uri "$base/apis/tap-generator/operations/create-tap/policies/policy?api-version=2022-08-01" `
    -Headers @{ Authorization = "Bearer $TOKEN" } `
    -ContentType "application/json" `
    -Body $opPayload | Out-Null
Write-OK "APIM operation policy (JWT + routing) applied"

# ── 6. GitHub Actions variables ───────────────────────────────────────────────
Write-Step "Setting GitHub Actions variables"

$vars = @{
    TENANT_ID            = $TENANT_ID
    UI_CLIENT_ID         = $UI_CLIENT_ID
    API_CLIENT_ID        = $API_CLIENT_ID
    APIM_BASE_URL        = $APIM_GATEWAY
    UI_APP_SERVICE_NAME  = $UI_APP_NAME
    API_APP_SERVICE_NAME = $API_APP_NAME
    RESOURCE_GROUP       = $RESOURCE_GROUP
    AZURE_TENANT_ID      = $TENANT_ID
    AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID
}

foreach ($kv in $vars.GetEnumerator()) {
    gh variable set $kv.Key --body $kv.Value --repo $GITHUB_REPO 2>$null | Out-Null
    Write-OK "Set: $($kv.Key)"
}

# AZURE_CLIENT_ID needs a federated credential – remind user
Write-Host ""
Write-Host "  NOTE: AZURE_CLIENT_ID (for OIDC) must be set separately." -ForegroundColor Yellow
Write-Host "  Run 04-github-oidc.ps1 or set it manually after creating a User-Assigned MI." -ForegroundColor Yellow

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "CONFIGURATION COMPLETE" -ForegroundColor Green
Write-Host "  UI  URL   : https://$UI_HOSTNAME"
Write-Host "  API URL   : https://$API_HOSTNAME/health"
Write-Host "  APIM URL  : $APIM_GATEWAY/tap/api/tap"
Write-Host "  MI obj ID : $MI_OBJECT_ID"
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Run: .\deploy\04-deploy.ps1  (triggers GitHub Actions)"
Write-Host "  2. After deploy completes, run: .\deploy\05-validate.ps1"
