$resourceGroup = "airg-platform-rg"
$apimName      = "apim-tap-prod"
$apiId         = "tap-generator"
$operationId   = "create-tap"
$tenantId      = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId   = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$uiOrigin      = "https://tap-gvfqfhc9g5chceg4.westus2-01.azurewebsites.net"
$apiBackend    = "https://asp-tap-generator-api-esfafpasfgg0bkbt.westus2-01.azurewebsites.net"
$apiVer        = "2022-08-01"

$subId   = (az account show | ConvertFrom-Json).id
Write-Host "Subscription: $subId" -ForegroundColor Gray
$base    = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName"

function Push-Policy($url, $xml, $label) {
    $xml = $xml.TrimStart([char]0xFEFF).Trim()
    $tmp = [System.IO.Path]::GetTempFileName() + ".xml"
    [System.IO.File]::WriteAllBytes($tmp, (New-Object System.Text.UTF8Encoding($false)).GetBytes($xml))
    $out = az rest --method PUT --url $url `
        --headers "Content-Type=application/vnd.ms-azure-apim.policy+xml" "If-Match=*" `
        --body "@$tmp" 2>&1
    Remove-Item $tmp -Force
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED [$label]: $out" -ForegroundColor Red
        exit 1
    }
    Write-Host "OK: $label" -ForegroundColor Green
}

# ── All-operations policy (CORS only) ────────────────────────────────────────
$allOpsXml = @'
<policies>
  <inbound>
    <cors allow-credentials="true">
      <allowed-origins><origin>__UI_ORIGIN__</origin></allowed-origins>
      <allowed-methods preflight-result-max-age="300">
        <method>POST</method><method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers><header>*</header></allowed-headers>
      <expose-headers><header>*</header></expose-headers>
    </cors>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'@ -replace '__UI_ORIGIN__', $uiOrigin

Push-Policy "$base/apis/$apiId/policies/policy?api-version=$apiVer" $allOpsXml "All-operations CORS"

# ── Operation policy (JWT + backend + on-error) ───────────────────────────────
$opXml = @'
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401"
        failed-validation-error-message="Unauthorized: valid Bearer token with TAP.Generator role required."
        require-expiration-time="true" require-signed-tokens="true">
      <openid-config url="https://login.microsoftonline.com/__TENANT_ID__/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>__API_CLIENT_ID__</audience>
        <audience>api://__API_CLIENT_ID__</audience>
      </audiences>
      <issuers>
        <issuer>https://login.microsoftonline.com/__TENANT_ID__/v2.0</issuer>
        <issuer>https://sts.windows.net/__TENANT_ID__/</issuer>
      </issuers>
      <required-claims>
        <claim name="roles" match="any" separator=" "><value>TAP.Generator</value></claim>
      </required-claims>
    </validate-jwt>
    <set-backend-service base-url="__API_BACKEND__" />
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
      <value>__UI_ORIGIN__</value>
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
'@ -replace '__TENANT_ID__',      $tenantId `
   -replace '__API_CLIENT_ID__',  $apiClientId `
   -replace '__API_BACKEND__',    $apiBackend `
   -replace '__UI_ORIGIN__',      $uiOrigin

Push-Policy "$base/apis/$apiId/operations/$operationId/policies/policy?api-version=$apiVer" $opXml "Generate TAP operation"

Write-Host ""
Write-Host "All policies applied. Testing endpoint..." -ForegroundColor Cyan
$result = curl.exe -s -o - -w "`nHTTP_STATUS:%{http_code}" -X POST "https://apim-tap-prod.azure-api.net/tap/api/tap" -H "Content-Type: application/json" -d '{"targetUpn":"test","lifetimeInMinutes":15}'
Write-Host $result
