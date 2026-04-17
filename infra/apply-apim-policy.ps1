$resourceGroup  = "airg-platform-rg"
$apimName       = "apim-tap-prod"
$apiId          = "tap-generator"
$tenantId       = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId    = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$uiOrigin       = "https://tap-gvfqfhc9g5chceg4.westus2-01.azurewebsites.net"
$apiBackend     = "https://asp-tap-generator-api.azurewebsites.net"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
$subId = (az account show | ConvertFrom-Json).id
Write-Host "Subscription: $subId" -ForegroundColor Gray

# ── Step 1: Confirm API exists ────────────────────────────────────────────────
Write-Host ""
Write-Host "Checking API exists in APIM..." -ForegroundColor Cyan
az apim api show `
    --service-name $apimName `
    --resource-group $resourceGroup `
    --api-id $apiId 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "API '$apiId' not found in '$apimName'. Creating it now..." -ForegroundColor Yellow
    az apim api create `
        --service-name $apimName `
        --resource-group $resourceGroup `
        --api-id $apiId `
        --path "tap" `
        --display-name "TAP Generator API" `
        --protocols https `
        --service-url $apiBackend
    Write-Host "API created." -ForegroundColor Green
} else {
    Write-Host "API found." -ForegroundColor Green
}

# ── Step 2: Build raw XML policy ─────────────────────────────────────────────
$policyXml = @"
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized" require-expiration-time="true" require-signed-tokens="true">
      <openid-config url="https://login.microsoftonline.com/$tenantId/v2.0/.well-known/openid-configuration" />
      <audiences><audience>api://$apiClientId</audience></audiences>
      <issuers>
        <issuer>https://login.microsoftonline.com/$tenantId/v2.0</issuer>
        <issuer>https://sts.windows.net/$tenantId/</issuer>
      </issuers>
      <required-claims>
        <claim name="roles" match="any" separator=" "><value>TAP.Generator</value></claim>
      </required-claims>
    </validate-jwt>
    <cors allow-credentials="true">
      <allowed-origins><origin>$uiOrigin</origin></allowed-origins>
      <allowed-methods preflight-result-max-age="300">
        <method>POST</method><method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>Authorization</header>
        <header>Content-Type</header>
        <header>X-Request-Id</header>
      </allowed-headers>
      <expose-headers><header>X-Request-Id</header></expose-headers>
    </cors>
    <set-backend-service base-url="$apiBackend" />
    <set-header name="X-Request-Id" exists-action="skip">
      <value>@(Guid.NewGuid().ToString())</value>
    </set-header>
  </inbound>
  <backend><base /></backend>
  <outbound>
    <base />
    <set-header name="X-Powered-By" exists-action="delete" />
    <set-header name="Server" exists-action="delete" />
  </outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="500" reason="Internal Server Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error", context.LastError.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
"@

# ── Step 3: PUT using raw XML body (avoids JSON escaping issues) ──────────────
$url = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/$apiId/policies/policy?api-version=2022-08-01"

$xmlFile = [System.IO.Path]::GetTempFileName() + ".xml"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllBytes($xmlFile, $utf8NoBom.GetBytes($policyXml))

Write-Host ""
Write-Host "Applying policy (raw XML)..." -ForegroundColor Cyan

# Show full response for debugging
$response = az rest --method PUT --url $url `
    --headers "Content-Type=application/vnd.ms-azure-apim.policy+xml" `
    --body "@$xmlFile" 2>&1
Write-Host "Response: $response"
Remove-Item $xmlFile -Force

# ── Step 4: Verify via GET ────────────────────────────────────────────────────
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
Start-Sleep -Seconds 3
$check    = az rest --method GET --url $url 2>$null | ConvertFrom-Json

if ($check -and $check.properties.value.Length -gt 50) {
    Write-Host "Policy applied successfully." -ForegroundColor Green
    Write-Host "Policy length: $($check.properties.value.Length) chars"
} else {
    Write-Host "Policy still not saved. Check response above for details." -ForegroundColor Red
}
