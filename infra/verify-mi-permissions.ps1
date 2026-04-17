$miObjectId = "5906180b-d377-4856-aacf-1b09cba28655"
$graphAppId  = "00000003-0000-0000-c000-000000000000"

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Application.Read.All" -UseDeviceCode -NoWelcome

Write-Host ""
Write-Host "Checking permissions assigned to MI: $miObjectId" -ForegroundColor Cyan

$graphSp     = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
$assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $miObjectId

$required = @("UserAuthenticationMethod.ReadWrite.All", "User.Read.All")
$results  = @()

foreach ($perm in $required) {
    $role   = $graphSp.AppRoles | Where-Object { $_.Value -eq $perm }
    $assigned = $assignments | Where-Object { $_.AppRoleId -eq $role.Id }
    $results += [PSCustomObject]@{
        Permission = $perm
        Status     = if ($assigned) { "ASSIGNED" } else { "MISSING" }
    }
}

Write-Host ""
$results | Format-Table -AutoSize

$missing = $results | Where-Object { $_.Status -eq "MISSING" }
if ($missing) {
    Write-Host "Some permissions are missing. Re-run assign-mi-permissions.ps1." -ForegroundColor Red
} else {
    Write-Host "All required permissions are correctly assigned." -ForegroundColor Green
}
