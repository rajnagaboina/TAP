# Push operation policy from apim-policy-payload.json to live APIM
# Run: .\infra\push-apim-policy.ps1

$SUBSCRIPTION_ID = "fb8e0ac3-018c-4a81-85ac-64d70878a7b7"
$RESOURCE_GROUP  = "airg-platform-rg"
$APIM_NAME       = "apim-tap-prod"

$TOKEN = (az account get-access-token --resource "https://management.azure.com/" --query accessToken -o tsv)
$payload = Get-Content "$PSScriptRoot\apim-policy-payload.json" -Raw

$uri = "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/apis/tap-generator/operations/create-tap/policies/policy?api-version=2022-08-01"

Invoke-RestMethod -Method PUT -Uri $uri `
    -Headers @{ Authorization = "Bearer $TOKEN" } `
    -ContentType "application/json" `
    -Body $payload | Out-Null

Write-Host "Policy pushed." -ForegroundColor Green

# Verify
$result = Invoke-RestMethod -Method GET -Uri $uri `
    -Headers @{ Authorization = "Bearer $TOKEN" }
Write-Host "Live policy value (first 200 chars):" -ForegroundColor Cyan
Write-Host $result.properties.value.Substring(0, [Math]::Min(200, $result.properties.value.Length))
