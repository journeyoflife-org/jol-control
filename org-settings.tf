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
