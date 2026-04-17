# =============================================================================
# config.ps1  –  Fill in ALL values before running any deploy script.
# =============================================================================

# ── Azure ─────────────────────────────────────────────────────────────────────
$TENANT_ID        = "ac1cd4e7-b14c-42dd-aac0-7543da3fb35f"
$SUBSCRIPTION_ID  = "fb8e0ac3-018c-4a81-85ac-64d70878a7b7"
$RESOURCE_GROUP   = "airg-platform-rg"
$LOCATION         = "westus2"

# ── App Services ──────────────────────────────────────────────────────────────
$API_APP_NAME     = "asp-tap-generator-api"      # .NET backend
$UI_APP_NAME      = "tap"                        # Flutter web
$APP_PLAN_API     = "asp-tap-api-plan"
$APP_PLAN_UI      = "asp-tap-ui-plan"
$APP_SKU          = "B1"

# ── APIM ──────────────────────────────────────────────────────────────────────
$APIM_NAME        = "apim-tap-prod"
$APIM_EMAIL       = "rajnagaboina1982@gmail.com"
$APIM_ORG         = "IAM Platform Team"

# ── App Insights ──────────────────────────────────────────────────────────────
$APPINSIGHTS_NAME = "tap"

# ── Entra App Registrations ───────────────────────────────────────────────────
$API_APP_REG_NAME = "TAP Generator API"
$UI_APP_REG_NAME  = "TAP Generator UI"
$OPERATORS_GROUP  = "SG-IAM-TAP-Generators"

# ── GitHub ────────────────────────────────────────────────────────────────────
$GITHUB_REPO      = "rajnagaboina/TAP"           # owner/repo
