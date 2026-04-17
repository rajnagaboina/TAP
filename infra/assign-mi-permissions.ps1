param(
    [string]$MiObjectId = "5906180b-d377-4856-aacf-1b09cba28655"
)

$graphAppId = "00000003-0000-0000-c000-000000000000"
$permissions = @("UserAuthenticationMethod.ReadWrite.All", "User.Read.All")

Write-Host "Logging in via Azure CLI..." -ForegroundColor Cyan
az login --use-device-code
az account show

# ── Verify MI service principal exists (may take a few minutes after enabling) ─
Write-Host ""
Write-Host "Looking up MI service principal $MiObjectId..." -ForegroundColor Cyan
$miSp = $null
$retries = 6
for ($i = 1; $i -le $retries; $i++) {
    $miSp = az ad sp show --id $MiObjectId 2>$null | ConvertFrom-Json
    if ($miSp) { break }
    Write-Host "  Not found yet, waiting 15s... ($i/$retries)" -ForegroundColor Yellow
    Start-Sleep -Seconds 15
}
if (-not $miSp) {
    Write-Host "ERROR: Service principal $MiObjectId not found after $($retries * 15)s." -ForegroundColor Red
    Write-Host "Check: Portal → App Service asp-tap-generator-api → Identity → System assigned → the Object ID shown there." -ForegroundColor Yellow
    exit 1
}
Write-Host "Found MI SP: $($miSp.displayName) [$($miSp.id)]" -ForegroundColor Green

# ── Get Graph SP ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Resolving Microsoft Graph service principal..." -ForegroundColor Cyan
$graphSp = az ad sp show --id $graphAppId | ConvertFrom-Json
if (-not $graphSp) { Write-Host "ERROR: Could not find Microsoft Graph SP." -ForegroundColor Red; exit 1 }
Write-Host "Found: $($graphSp.displayName) [$($graphSp.id)]" -ForegroundColor Green

# ── Assign each permission ────────────────────────────────────────────────────
foreach ($permName in $permissions) {
    Write-Host ""
    Write-Host "Processing: $permName" -ForegroundColor Cyan

    $role = $graphSp.appRoles | Where-Object { $_.value -eq $permName }
    if (-not $role) { Write-Warning "Role '$permName' not found. Skipping."; continue }

    # Check existing
    $assignments = az rest --method GET `
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/$MiObjectId/appRoleAssignments" `
        2>$null | ConvertFrom-Json
    $alreadyAssigned = $assignments.value | Where-Object { $_.appRoleId -eq $role.id }

    if ($alreadyAssigned) {
        Write-Host "  Already assigned - skipping." -ForegroundColor Yellow
        continue
    }

    # Write body to temp file to avoid Windows quoting issues
    $bodyFile = [System.IO.Path]::GetTempFileName() + ".json"
    @{
        principalId = $MiObjectId
        resourceId  = $graphSp.id
        appRoleId   = $role.id
    } | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText($bodyFile, $_, (New-Object System.Text.UTF8Encoding $false)) }

    az rest `
        --method POST `
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/$MiObjectId/appRoleAssignments" `
        --headers "Content-Type=application/json" `
        --body "@$bodyFile" | Out-Null

    Remove-Item $bodyFile -Force

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Assigned successfully." -ForegroundColor Green
    } else {
        Write-Host "  Assignment failed." -ForegroundColor Red
    }
}

# ── Verify ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Verifying final assignments..." -ForegroundColor Cyan
$final = az rest --method GET `
    --url "https://graph.microsoft.com/v1.0/servicePrincipals/$MiObjectId/appRoleAssignments" | ConvertFrom-Json

$final.value | ForEach-Object {
    $roleName = ($graphSp.appRoles | Where-Object { $_.id -eq $_.appRoleId }).value
    [PSCustomObject]@{
        Permission           = $roleName
        ResourceDisplayName  = $_.resourceDisplayName
        PrincipalDisplayName = $_.principalDisplayName
    }
} | Format-Table -AutoSize

Write-Host "Total assignments: $($final.value.Count)" -ForegroundColor $(if ($final.value.Count -ge 2) {"Green"} else {"Red"})
