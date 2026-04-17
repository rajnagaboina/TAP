$resourceGroup = "airg-platform-rg"
$apimName      = "apim-tap-prod"
$apiId         = "tap-generator"
$tenantId      = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$apiClientId   = "6b1a0438-1405-45dc-a09c-d3282d41e37c"
$uiOrigin      = "https://tap-gvfqfhc9g5chceg4.westus2-01.azurewebsites.net"
$apiBackend    = "https://asp-tap-generator-api.azurewebsites.net"

Write-Host "Logging in..." -ForegroundColor Cyan
az login --use-device-code
$subId = (az account show | ConvertFrom-Json).id

# Write policy XML to temp file (no BOM)
$policyXml = @"
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized" require-expiration-time="true" require-signed-tokens="true">
      <openid-config url="https://login.microsoftonline.com/${tenantId}/v2.0/.well-known/openid-configuration" />
      <audiences><audience>api://${apiClientId}</audience></audiences>
      <issuers>
        <issuer>https://login.microsoftonline.com/${tenantId}/v2.0</issuer>
        <issuer>https://sts.windows.net/${tenantId}/</issuer>
      </issuers>
      <required-claims>
        <claim name="roles" match="any" separator=" "><value>TAP.Generator</value></claim>
      </required-claims>
    </validate-jwt>
    <cors allow-credentials="true">
      <allowed-origins><origin>${uiOrigin}</origin></allowed-origins>
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
    <set-backend-service base-url="${apiBackend}" />
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

$tmpXml = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.xml'
[System.IO.File]::WriteAllText($tmpXml, $policyXml, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Policy written to: $tmpXml" -ForegroundColor Gray

# Use az apim api policy create (CLI command, not REST)
Write-Host ""
Write-Host "Applying policy via az apim api policy create..." -ForegroundColor Cyan
az apim api policy create `
    --service-name $apimName `
    --resource-group $resourceGroup `
    --api-id $apiId `
    --policy-format rawxml `
    --value "@$tmpXml"

$exitCode = $LASTEXITCODE
Remove-Item $tmpXml -Force

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "CLI command failed (exit $exitCode). Trying REST PUT instead..." -ForegroundColor Yellow

    # Fallback: REST PUT with JSON wrapper containing XML as escaped string
    $xmlEscaped = $policyXml -replace '"', '\"' -replace "`r`n", '\n' -replace "`n", '\n'
    $jsonBody   = "{`"properties`":{`"format`":`"rawxml`",`"value`":`"$xmlEscaped`"}}"

    $jsonFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
    [System.IO.File]::WriteAllText($jsonFile, $jsonBody, (New-Object System.Text.UTF8Encoding $false))

    $putUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/$apiId/policies/policy?api-version=2022-08-01"
    az rest --method PUT --url $putUrl `
        --headers "Content-Type=application/json" `
        --body "@$jsonFile"

    Remove-Item $jsonFile -Force
}

# Verify
Write-Host ""
Write-Host "Verifying policy..." -ForegroundColor Cyan
Start-Sleep -Seconds 2
$verifyUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$resourceGroup/providers/Microsoft.ApiManagement/service/$apimName/apis/$apiId/policies/policy?api-version=2022-08-01"
$result    = az rest --method GET --url $verifyUrl 2>$null
Write-Host "GET response length: $($result.Length) chars"

if ($result -and $result.Length -gt 50) {
    Write-Host "Policy applied and verified." -ForegroundColor Green
} else {
    Write-Host "Policy may not have saved. Response: $result" -ForegroundColor Red
}
