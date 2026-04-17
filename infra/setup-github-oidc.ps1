$appName       = "tap-github-actions"
$resourceGroup = "airg-platform-rg"
$apiRG         = "airg-platform-rg"   # same RG for API App Service
$repoOwner     = "rajnagaboina"
$repoName      = "TAP"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
$subId    = (az account show | ConvertFrom-Json).id
$tenantId = (az account show | ConvertFrom-Json).tenantId
Write-Host "Subscription: $subId" -ForegroundColor Gray

# ── 1. Create App Registration ────────────────────────────────────────────────
Write-Host ""
Write-Host "Creating App Registration: $appName..." -ForegroundColor Cyan
$existing = az ad app list --display-name $appName --query "[0].appId" -o tsv 2>$null
if ($existing) {
    Write-Host "App already exists: $existing" -ForegroundColor Yellow
    $appId    = $existing
    $objectId = az ad app show --id $appId --query id -o tsv
} else {
    $app      = az ad app create --display-name $appName | ConvertFrom-Json
    $appId    = $app.appId
    $objectId = $app.id
    Write-Host "Created: $appId" -ForegroundColor Green
}

# ── 2. Create Service Principal ───────────────────────────────────────────────
Write-Host ""
Write-Host "Creating Service Principal..." -ForegroundColor Cyan
$spExists = az ad sp show --id $appId 2>$null | ConvertFrom-Json
if (-not $spExists) {
    az ad sp create --id $appId | Out-Null
    Write-Host "Service Principal created." -ForegroundColor Green
} else {
    Write-Host "Service Principal already exists." -ForegroundColor Yellow
}
$spId = az ad sp show --id $appId --query id -o tsv

# ── 3. Add Federated Credentials for GitHub Actions ───────────────────────────
Write-Host ""
Write-Host "Adding federated credentials..." -ForegroundColor Cyan

$credentials = @(
    @{ name = "github-main-branch"; subject = "repo:${repoOwner}/${repoName}:ref:refs/heads/main" },
    @{ name = "github-pull-request"; subject = "repo:${repoOwner}/${repoName}:pull_request" }
)

foreach ($cred in $credentials) {
    $existing = az ad app federated-credential list --id $objectId --query "[?name=='$($cred.name)'].name" -o tsv 2>$null
    if ($existing) {
        Write-Host "  Credential '$($cred.name)' already exists, skipping." -ForegroundColor Yellow
        continue
    }
    $body = @{
        name        = $cred.name
        issuer      = "https://token.actions.githubusercontent.com"
        subject     = $cred.subject
        description = "GitHub Actions OIDC for $repoOwner/$repoName"
        audiences   = @("api://AzureADTokenExchange")
    } | ConvertTo-Json

    $tmpFile = [System.IO.Path]::GetTempFileName() + ".json"
    [System.IO.File]::WriteAllText($tmpFile, $body, (New-Object System.Text.UTF8Encoding $false))
    az ad app federated-credential create --id $objectId --parameters "@$tmpFile" | Out-Null
    Remove-Item $tmpFile -Force
    Write-Host "  Added: $($cred.name)" -ForegroundColor Green
}

# ── 4. Assign Contributor on both resource groups ─────────────────────────────
Write-Host ""
Write-Host "Assigning Contributor role..." -ForegroundColor Cyan

foreach ($rg in @($resourceGroup, $apiRG) | Select-Object -Unique) {
    $scope    = "/subscriptions/$subId/resourceGroups/$rg"
    $existing = az role assignment list --assignee $spId --role Contributor --scope $scope --query "[0].id" -o tsv 2>$null
    if ($existing) {
        Write-Host "  Contributor already assigned on $rg" -ForegroundColor Yellow
    } else {
        az role assignment create --assignee $spId --role Contributor --scope $scope | Out-Null
        Write-Host "  Contributor assigned on $rg" -ForegroundColor Green
    }
}

# ── 5. Set GitHub Secrets ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "Setting GitHub Actions secrets..." -ForegroundColor Cyan

$repoPath = "$repoOwner/$repoName"
$appIdFull = az ad app show --id $appId --query appId -o tsv

gh secret set AZURE_CLIENT_ID     --body $appIdFull --repo $repoPath
gh secret set AZURE_TENANT_ID     --body $tenantId  --repo $repoPath
gh secret set AZURE_SUBSCRIPTION_ID --body $subId   --repo $repoPath

Write-Host ""
Write-Host "=======================================" -ForegroundColor Green
Write-Host "OIDC Setup Complete!" -ForegroundColor Green
Write-Host "  App Registration : $appName ($appIdFull)" -ForegroundColor White
Write-Host "  GitHub Secrets   : AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor Green
