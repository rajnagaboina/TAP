$resourceGroup  = "airg-platform-rg"
$apimName       = "apim-tap-prod"
$apiId          = "tap-generator"
$operationId    = "create-tap"
$tenantId       = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId    = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$uiOrigin       = "https://tap-gvfqfhc9g5chceg4.westus2-01.azurewebsites.net"
$apiBackend     = "https://asp-tap-generator-api-esfafpasfgg0bkbt.westus2-01.azurewebsites.net"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
$subId = (az account show | ConvertFrom-Json).id
Write-Host "Subscription: $subId" -ForegroundColor Gray

$baseUrl   = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName"
$apiVer    = "api-version=2022-08-01"

# ── Step 1: Ensure API exists ─────────────────────────────────────────────────
Write-Host ""
Write-Host "Checking API exists..." -ForegroundColor Cyan
az apim api show --service-name $apimName --resource-group $resourceGroup --api-id $apiId 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "API not found. Creating..." -ForegroundColor Yellow
    az apim api create `
        --service-name $apimName --resource-group $resourceGroup `
        --api-id $apiId --path "tap" --display-name "TAP Generator API" `
        --protocols https --service-url $apiBackend
    if ($LASTEXITCODE -ne 0) { Write-Host "API creation failed." -ForegroundColor Red; exit 1 }
    Write-Host "API created." -ForegroundColor Green
} else {
    Write-Host "API found." -ForegroundColor Green
}

# ── Step 2: Ensure POST /api/tap operation exists ─────────────────────────────
Write-Host ""
Write-Host "Checking operation exists..." -ForegroundColor Cyan
az apim api operation show --service-name $apimName --resource-group $resourceGroup `
    --api-id $apiId --operation-id $operationId 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Operation not found. Creating..." -ForegroundColor Yellow
    az apim api operation create `
        --service-name $apimName --resource-group $resourceGroup `
        --api-id $apiId --operation-id $operationId `
        --display-name "Generate TAP" --method POST --url-template "/api/tap"
    if ($LASTEXITCODE -ne 0) { Write-Host "Operation creation failed." -ForegroundColor Red; exit 1 }
    Write-Host "Operation created." -ForegroundColor Green
} else {
    Write-Host "Operation found." -ForegroundColor Green
}

# ── Step 3: All-operations policy (CORS only for OPTIONS preflight) ───────────
Write-Host ""
Write-Host "Applying All-operations policy..." -ForegroundColor Cyan

$allOpsXml = @'
<policies>
  <inbound>
    <cors allow-credentials="true">
      <allowed-origins><origin>UI_ORIGIN</origin></allowed-origins>
      <allowed-methods preflight-result-max-age="300">
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers><header>*</header></allowed-headers>
      <expose-headers><header>*</header></expose-headers>
    </cors>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'@ -replace 'UI_ORIGIN', $uiOrigin

$allOpsUrl  = "$baseUrl/apis/$apiId/policies/policy?$apiVer"
$allOpsFile = [System.IO.Path]::GetTempFileName() + ".xml"
[System.IO.File]::WriteAllBytes($allOpsFile, (New-Object System.Text.UTF8Encoding($false)).GetBytes($allOpsXml))
az rest --method PUT --url $allOpsUrl `
    --headers "Content-Type=application/vnd.ms-azure-apim.policy+xml" "If-Match=*" `
    --body "@$allOpsFile" | Out-Null
Remove-Item $allOpsFile -Force
if ($LASTEXITCODE -ne 0) { Write-Host "All-operations policy failed." -ForegroundColor Red; exit 1 }
Write-Host "All-operations policy applied." -ForegroundColor Green

# ── Step 4: Operation-level policy (JWT + backend + on-error) ────────────────
Write-Host ""
Write-Host "Applying operation policy..." -ForegroundColor Cyan

$opXml = @'
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401"
        failed-validation-error-message="Unauthorized: valid Bearer token with TAP.Generator role required."
        require-expiration-time="true" require-signed-tokens="true">
      <openid-config url="https://login.microsoftonline.com/TENANT_ID/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>API_CLIENT_ID</audience>
        <audience>api://API_CLIENT_ID</audience>
      </audiences>
      <issuers>
        <issuer>https://login.microsoftonline.com/TENANT_ID/v2.0</issuer>
        <issuer>https://sts.windows.net/TENANT_ID/</issuer>
      </issuers>
      <required-claims>
        <claim name="roles" match="any" separator=" "><value>TAP.Generator</value></claim>
      </required-claims>
    </validate-jwt>
    <set-backend-service base-url="API_BACKEND" />
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
      <value>UI_ORIGIN</value>
    </set-header>
    <set-header name="Access-Control-Allow-Credentials" exists-action="override">
      <value>true</value>
    </set-header>
    <return-response>
      <set-status code="@(context.Response.StatusCode)" reason="@(context.Response.StatusReason)" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error", context.LastError.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'@ -replace 'TENANT_ID', $tenantId `
   -replace 'API_CLIENT_ID', $apiClientId `
   -replace 'API_BACKEND', $apiBackend `
   -replace 'UI_ORIGIN', $uiOrigin

$opUrl  = "$baseUrl/apis/$apiId/operations/$operationId/policies/policy?$apiVer"
$opFile = [System.IO.Path]::GetTempFileName() + ".xml"
[System.IO.File]::WriteAllBytes($opFile, (New-Object System.Text.UTF8Encoding($false)).GetBytes($opXml))
az rest --method PUT --url $opUrl `
    --headers "Content-Type=application/vnd.ms-azure-apim.policy+xml" "If-Match=*" `
    --body "@$opFile" | Out-Null
Remove-Item $opFile -Force
if ($LASTEXITCODE -ne 0) { Write-Host "Operation policy failed." -ForegroundColor Red; exit 1 }
Write-Host "Operation policy applied." -ForegroundColor Green

# ── Step 5: Verify ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
Start-Sleep -Seconds 3
$check = az rest --method GET --url $opUrl 2>$null | ConvertFrom-Json
if ($check -and $check.properties.value.Length -gt 100) {
    Write-Host "Policy verified OK. Length: $($check.properties.value.Length) chars" -ForegroundColor Green
} else {
    Write-Host "Verification failed. Check Azure portal." -ForegroundColor Red
}

Write-Host ""
Write-Host "All done." -ForegroundColor Green
