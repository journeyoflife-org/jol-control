# ──────────────────────────────────────────────────────────────────────────────
# Organization-level Settings — security & compliance baseline
# ──────────────────────────────────────────────────────────────────────────────
# These settings apply to the entire GitHub organization.
# SOC2 CC6.1 · ISO 27001 A.5.1 · GDPR Art. 32
# ──────────────────────────────────────────────────────────────────────────────

# ── Organization security-manager role assignment ────────────────────────────
# Uses the non-deprecated github_organization_role_team resource (replaces the
# deprecated github_organization_security_manager). The built-in
# "security_manager" role id is resolved at plan time from the org role list.
data "github_organization_roles" "all" {}

locals {
  security_manager_role_id = one([
    for r in data.github_organization_roles.all.roles :
    r.role_id if r.name == "security_manager"
  ])
}

resource "github_organization_role_team" "security_team" {
  count = local.security_manager_role_id != null ? 1 : 0

  team_slug = "platform-admins"
  role_id   = local.security_manager_role_id
}

# ── Webhook for audit-log streaming ──────────────────────────────────────────
# Only created in prod AND when a webhook URL is supplied (via TF_VAR_*), so an
# empty secret never produces a broken webhook resource.
resource "github_organization_webhook" "audit_stream" {
  count = var.environment == "prod" && var.audit_webhook_url != "" ? 1 : 0

  events = ["*"]

  configuration {
    url          = var.audit_webhook_url
    content_type = "json"
    insecure_ssl = false
    secret       = var.audit_webhook_secret
  }

  active = true
}
