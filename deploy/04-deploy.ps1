# =============================================================================
# 04-deploy.ps1  –  Trigger GitHub Actions to build and deploy API + UI.
#
# Prerequisites:
#   - 03-configure.ps1 completed
#   - gh cli logged in (gh auth login)
#   - AZURE_CLIENT_ID GitHub variable set (see note in 03-configure.ps1)
#
# Run time: ~5 minutes
# =============================================================================
. "$PSScriptRoot\config.ps1"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    FAIL: $msg" -ForegroundColor Red; exit 1 }

# ── 1. Trigger API deployment ─────────────────────────────────────────────────
Write-Step "Triggering API deployment"
gh workflow run "api-deploy.yml" --repo $GITHUB_REPO --ref main
if ($LASTEXITCODE -ne 0) { Write-Fail "Could not trigger API workflow" }
Write-OK "API workflow triggered"

Start-Sleep -Seconds 5

# ── 2. Trigger UI deployment ──────────────────────────────────────────────────
Write-Step "Triggering UI deployment"
gh workflow run "ui-deploy.yml" --repo $GITHUB_REPO --ref main
if ($LASTEXITCODE -ne 0) { Write-Fail "Could not trigger UI workflow" }
Write-OK "UI workflow triggered"

# ── 3. Wait and watch ─────────────────────────────────────────────────────────
Write-Step "Waiting for deployments to complete (~3 minutes)..."
Write-Host "    You can also watch progress at: https://github.com/$GITHUB_REPO/actions" -ForegroundColor Gray

$timeout    = 300   # 5 minutes
$interval   = 15
$elapsed    = 0
$apiDone    = $false
$uiDone     = $false

while ($elapsed -lt $timeout -and (-not $apiDone -or -not $uiDone)) {
    Start-Sleep -Seconds $interval
    $elapsed += $interval

    $runs = gh run list --repo $GITHUB_REPO --limit 6 --json name,status,conclusion,startedAt | ConvertFrom-Json

    if (-not $apiDone) {
        $apiRun = $runs | Where-Object { $_.name -like "*API*" -or $_.name -like "*api*" } | Select-Object -First 1
        if ($apiRun -and $apiRun.status -eq "completed") {
            if ($apiRun.conclusion -eq "success") { Write-OK "API deployment succeeded"; $apiDone = $true }
            else { Write-Fail "API deployment failed (conclusion: $($apiRun.conclusion))" }
        } else {
            Write-Host "    API: in progress... ($elapsed s)" -ForegroundColor Gray
        }
    }

    if (-not $uiDone) {
        $uiRun = $runs | Where-Object { $_.name -like "*Flutter*" -or $_.name -like "*UI*" } | Select-Object -First 1
        if ($uiRun -and $uiRun.status -eq "completed") {
            if ($uiRun.conclusion -eq "success") { Write-OK "UI deployment succeeded"; $uiDone = $true }
            else { Write-Fail "UI deployment failed (conclusion: $($uiRun.conclusion))" }
        } else {
            Write-Host "    UI:  in progress... ($elapsed s)" -ForegroundColor Gray
        }
    }
}

if (-not $apiDone -or -not $uiDone) {
    Write-Host ""
    Write-Host "  Timed out waiting. Check: https://github.com/$GITHUB_REPO/actions" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "BOTH DEPLOYMENTS COMPLETE" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "  Run: .\deploy\05-validate.ps1"
}
