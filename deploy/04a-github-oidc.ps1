# =============================================================================
# 04a-github-oidc.ps1  –  Create User-Assigned Managed Identity with federated
#                          credentials for GitHub Actions OIDC (no secrets).
#
# Prerequisites:
#   - 03-configure.ps1 completed
#   - az cli logged in with Owner/User Access Administrator on the subscription
#   - gh cli logged in
#
# Run time: ~1 minute
# Safe to re-run.
# =============================================================================
. "$PSScriptRoot\config.ps1"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    FAIL: $msg" -ForegroundColor Red; exit 1 }

az account set --subscription $SUBSCRIPTION_ID

$MI_NAME = "mi-github-actions-tap"

# ── 1. Create User-Assigned Managed Identity ──────────────────────────────────
Write-Step "User-Assigned Managed Identity: $MI_NAME"

$mi = az identity show --name $MI_NAME --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json
if (-not $mi) {
    $mi = az identity create `
        --name $MI_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $LOCATION | ConvertFrom-Json
    Write-OK "Created: $($mi.clientId)"
} else {
    Write-OK "Already exists: $($mi.clientId)"
}

$MI_CLIENT_ID   = $mi.clientId
$MI_PRINCIPAL_ID = $mi.principalId
$MI_RESOURCE_ID  = $mi.id

# ── 2. Grant Contributor on resource group (for webapp deploy) ────────────────
Write-Step "Assigning Contributor role on resource group"

$scope = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
$existing = az role assignment list `
    --assignee $MI_PRINCIPAL_ID `
    --role Contributor `
    --scope $scope 2>$null | ConvertFrom-Json

if (-not $existing -or $existing.Count -eq 0) {
    az role assignment create `
        --assignee $MI_PRINCIPAL_ID `
        --role Contributor `
        --scope $scope | Out-Null
    Write-OK "Contributor assigned on $RESOURCE_GROUP"
} else {
    Write-OK "Contributor already assigned"
}

# ── 3. Add federated credentials for GitHub Actions ───────────────────────────
Write-Step "Federated credentials for GitHub Actions"

$repo   = $GITHUB_REPO   # e.g. "owner/repo"
$creds  = @(
    @{ name = "github-main";          subject = "repo:${repo}:ref:refs/heads/main"        },
    @{ name = "github-pr";            subject = "repo:${repo}:pull_request"                },
    @{ name = "github-env-production"; subject = "repo:${repo}:environment:production"     }
)

foreach ($cred in $creds) {
    $existing = az identity federated-credential show `
        --name $cred.name `
        --identity-name $MI_NAME `
        --resource-group $RESOURCE_GROUP 2>$null | ConvertFrom-Json

    if (-not $existing) {
        az identity federated-credential create `
            --name $cred.name `
            --identity-name $MI_NAME `
            --resource-group $RESOURCE_GROUP `
            --issuer "https://token.actions.githubusercontent.com" `
            --subject $cred.subject `
            --audiences "api://AzureADTokenExchange" | Out-Null
        Write-OK "Created credential: $($cred.name)"
    } else {
        Write-OK "Already exists: $($cred.name)"
    }
}

# ── 4. Set AZURE_CLIENT_ID GitHub variable ────────────────────────────────────
Write-Step "Setting AZURE_CLIENT_ID GitHub variable"

gh variable set AZURE_CLIENT_ID --body $MI_CLIENT_ID --repo $GITHUB_REPO 2>$null | Out-Null
Write-OK "AZURE_CLIENT_ID = $MI_CLIENT_ID"

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "OIDC SETUP COMPLETE" -ForegroundColor Green
Write-Host "  MI Name       : $MI_NAME"
Write-Host "  Client ID     : $MI_CLIENT_ID"
Write-Host "  Principal ID  : $MI_PRINCIPAL_ID"
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "GitHub Actions workflows must use:" -ForegroundColor Yellow
Write-Host "  permissions:"
Write-Host "    id-token: write"
Write-Host "    contents: read"
Write-Host ""
Write-Host "  - uses: azure/login@v2"
Write-Host "    with:"
Write-Host "      client-id: `${{ vars.AZURE_CLIENT_ID }}"
Write-Host "      tenant-id: `${{ vars.AZURE_TENANT_ID }}"
Write-Host "      subscription-id: `${{ vars.AZURE_SUBSCRIPTION_ID }}"
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  Run: .\deploy\04-deploy.ps1"
