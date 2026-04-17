$resourceGroup   = "airg-platform-rg"
$location        = "westus2"
$apimName        = "apim-tap-prod"
$publisherEmail  = "rajnagaboina1982@gmail.com"
$publisherName   = "IAM Platform Team"
$apimSku         = "Consumption"   # Instant provisioning; upgrade to Developer/Standard later if needed

$tenantId        = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId     = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$uiOrigin        = "https://tap-gvfqfhc9g5chceg4.westus2-01.azurewebsites.net"
$apiBackend      = "https://asp-tap-generator-api-esfafpasfgg0bkbt.westus2-01.azurewebsites.net"

$apiId           = "tap-generator"
$apiPath         = "tap"
$apiDisplayName  = "TAP Generator API"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
$subId = (az account show | ConvertFrom-Json).id
Write-Host "Subscription: $subId" -ForegroundColor Gray

# ── 1. Create APIM instance ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Creating APIM: $apimName (Consumption, $location)..." -ForegroundColor Cyan
Write-Host "This takes ~30 seconds for Consumption tier." -ForegroundColor Gray
az apim create `
    --name $apimName `
    --resource-group $resourceGroup `
    --location $location `
    --publisher-email $publisherEmail `
    --publisher-name $publisherName `
    --sku-name $apimSku

if ($LASTEXITCODE -ne 0) { Write-Host "APIM creation failed." -ForegroundColor Red; exit 1 }
Write-Host "APIM created." -ForegroundColor Green

$gatewayUrl = (az apim show --name $apimName --resource-group $resourceGroup | ConvertFrom-Json).gatewayUrl
Write-Host "Gateway URL: $gatewayUrl" -ForegroundColor Green

# ── 2. Create the API ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Creating API definition in APIM..." -ForegroundColor Cyan
az apim api create `
    --service-name $apimName `
    --resource-group $resourceGroup `
    --api-id $apiId `
    --path $apiPath `
    --display-name $apiDisplayName `
    --protocols https `
    --service-url $apiBackend

if ($LASTEXITCODE -ne 0) { Write-Host "API creation failed." -ForegroundColor Red; exit 1 }
Write-Host "API created." -ForegroundColor Green

# ── 3. Create POST /api/tap operation ─────────────────────────────────────────
Write-Host ""
Write-Host "Creating POST /api/tap operation..." -ForegroundColor Cyan
az apim api operation create `
    --service-name $apimName `
    --resource-group $resourceGroup `
    --api-id $apiId `
    --operation-id "create-tap" `
    --display-name "Generate TAP" `
    --method POST `
    --url-template "/api/tap"

Write-Host "Operation created." -ForegroundColor Green

# ── 4. Apply inbound policy ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Applying APIM policy..." -ForegroundColor Cyan

$policyXml = @"
<policies>
  <inbound>
    <base />
    <validate-jwt
        header-name="Authorization"
        failed-validation-httpcode="401"
        failed-validation-error-message="Unauthorized: valid Bearer token with TAP.Generator role required."
        require-expiration-time="true"
        require-signed-tokens="true">
      <openid-config url="https://login.microsoftonline.com/$tenantId/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>api://$apiClientId</audience>
      </audiences>
      <issuers>
        <issuer>https://login.microsoftonline.com/$tenantId/v2.0</issuer>
        <issuer>https://sts.windows.net/$tenantId/</issuer>
      </issuers>
      <required-claims>
        <claim name="roles" match="any" separator=" ">
          <value>TAP.Generator</value>
        </claim>
      </required-claims>
    </validate-jwt>
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
        <header>X-Request-Id</header>
      </allowed-headers>
      <expose-headers>
        <header>X-Request-Id</header>
      </expose-headers>
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
      <set-status code="@((int)context.LastError.StatusCode)" reason="@(context.LastError.Reason)" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@("{""error"": """ + context.LastError.Message + """}")</set-body>
    </return-response>
  </on-error>
</policies>
"@

$policyFile = [System.IO.Path]::GetTempFileName() + ".xml"
$policyXml | ForEach-Object { [System.IO.File]::WriteAllText($policyFile, $_, (New-Object System.Text.UTF8Encoding $false)) }

az apim api policy create `
    --service-name $apimName `
    --resource-group $resourceGroup `
    --api-id $apiId `
    --policy-format xml `
    --value "@$policyFile"

Remove-Item $policyFile -Force

if ($LASTEXITCODE -ne 0) { Write-Host "Policy apply failed." -ForegroundColor Red; exit 1 }
Write-Host "Policy applied." -ForegroundColor Green

# ── 5. Update azure-config.yaml ───────────────────────────────────────────────
Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================"
Write-Host "APIM Name    : $apimName"
Write-Host "Gateway URL  : $gatewayUrl"
Write-Host "API Path     : $gatewayUrl/$apiPath"
Write-Host "API Backend  : $apiBackend"
Write-Host ""
Write-Host "Update azure-config.yaml:" -ForegroundColor Yellow
Write-Host "  apim.name       = $apimName"
Write-Host "  apim.gatewayUrl = $gatewayUrl"
Write-Host "========================================"
Write-Host "APIM creation and configuration complete." -ForegroundColor Green
