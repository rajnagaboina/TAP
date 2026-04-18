# =============================================================================
# config.ps1  –  Fill in ONLY the 6 values below.
#                Everything else is auto-derived — do not edit below the line.
# =============================================================================

# ── FILL IN THESE 6 VALUES ────────────────────────────────────────────────────
$TENANT_ID       = ""        # az account show --query tenantId -o tsv
$SUBSCRIPTION_ID = ""        # az account show --query id -o tsv
$RESOURCE_GROUP  = ""        # e.g. "my-tap-rg"  (created if it doesn't exist)
$LOCATION        = ""        # e.g. "westus2", "eastus", "uksouth"
$APIM_EMAIL      = ""        # publisher notification email for APIM

# ── AUTO-DERIVED — DO NOT EDIT BELOW THIS LINE ────────────────────────────────

# Build a short safe prefix from the resource group name (max 12 alphanum chars)
$_prefix = ($RESOURCE_GROUP -replace "[^a-zA-Z0-9]", "").ToLower()
if ($_prefix.Length -gt 12) { $_prefix = $_prefix.Substring(0, 12) }

# App Services
$API_APP_NAME     = "tap-api-$_prefix"
$UI_APP_NAME      = "tap-ui-$_prefix"
$APP_PLAN_API     = "plan-tap-api-$_prefix"
$APP_PLAN_UI      = "plan-tap-ui-$_prefix"
$APP_SKU          = "B1"

# APIM
$APIM_NAME        = "apim-tap-$_prefix"
$APIM_ORG         = "IAM Platform Team"

# Application Insights
$APPINSIGHTS_NAME = "ai-tap-$_prefix"

# Entra App Registrations (display names — stable across environments)
$API_APP_REG_NAME = "TAP Generator API"
$UI_APP_REG_NAME  = "TAP Generator UI"
$OPERATORS_GROUP  = "SG-IAM-TAP-Generators"

# Validate required inputs
if (-not $TENANT_ID)       { throw "config.ps1: TENANT_ID is empty. Fill it in before running." }
if (-not $SUBSCRIPTION_ID) { throw "config.ps1: SUBSCRIPTION_ID is empty." }
if (-not $RESOURCE_GROUP)  { throw "config.ps1: RESOURCE_GROUP is empty." }
if (-not $LOCATION)        { throw "config.ps1: LOCATION is empty." }
if (-not $APIM_EMAIL)      { throw "config.ps1: APIM_EMAIL is empty." }
if (-not $GITHUB_REPO)     { throw "config.ps1: GITHUB_REPO is empty (format: owner/repo)." }
