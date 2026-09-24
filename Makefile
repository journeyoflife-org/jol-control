# ──────────────────────────────────────────────────────────────────────────────
# JOL Control Plane — Makefile
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: help validate plan apply fmt lint drift compliance clean

.DEFAULT_GOAL := help

# ── Help ─────────────────────────────────────────────────────────────────────
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Validation ───────────────────────────────────────────────────────────────
validate: ## Validate all repo YAML definitions
	python3 scripts/validate_repos.py

compliance: ## Run full compliance check
	python3 scripts/compliance_check.py

# ── Terraform ────────────────────────────────────────────────────────────────
init: ## Initialize Terraform
	terraform init -input=false

fmt: ## Format Terraform files
	terraform fmt -recursive

lint: fmt validate ## Run all linting (terraform fmt + YAML validation)

plan: validate ## Run terraform plan
	terraform plan -input=false -out=tfplan

apply: ## Apply terraform changes (use CI/CD instead!)
	@echo "WARNING: Use CI/CD pipeline for applies. Local apply is for emergencies only."
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	terraform apply -input=false tfplan

# ── Drift Detection ──────────────────────────────────────────────────────────
drift: ## Detect drift between definitions and GitHub
	python3 scripts/drift_detect.py

# ── Utilities ────────────────────────────────────────────────────────────────
list-repos: ## List all managed repositories
	@ls -1 repos/*.yml | sed 's|repos/||;s|\.yml||' | sort

count-repos: ## Count managed repositories
	@echo "Managed repositories: $$(ls -1 repos/*.yml | wc -l)"

clean: ## Remove generated files
	rm -f tfplan plan-output.txt compliance-report.json compliance-snapshot.json
