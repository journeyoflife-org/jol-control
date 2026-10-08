# ──────────────────────────────────────────────────────────────────────────────
# JOL Control Plane — Makefile
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: help validate plan plan-gate state-gate apply fmt lint drift compliance test clean init list-repos count-repos

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

test: ## Run gate self-tests (plan gate + state gate, no pytest required)
	python3 tests/test_plan_gate.py
	bash tests/test_state_gate.sh

# ── Terraform ────────────────────────────────────────────────────────────────
init: ## Initialize Terraform
	terraform init -input=false

fmt: ## Format Terraform files
	terraform fmt -recursive

lint: fmt validate ## Run all linting (terraform fmt + YAML validation)

plan: validate ## Run terraform plan
	terraform plan -input=false -out=tfplan

state-gate: ## STOP gate — halt when local state cannot account for this config
	python3 scripts/state_gate.py .

plan-gate: state-gate ## STOP gate — halt if the plan destroys or replaces anything
	terraform show -json tfplan > tfplan.json
	python3 scripts/plan_gate.py tfplan.json

apply: plan-gate ## Apply the saved plan (blocked when either gate halts)
	@echo "WARNING: this host holds the only copy of terraform.tfstate."
	@echo "         CI cannot apply — it has no access to this state."
	@echo "         state-gate: the state file accounts for what this config declares."
	@echo "         plan-gate: the plan contains no destroy/replace actions."
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
	rm -f tfplan tfplan.json plan-output.txt compliance-report.json compliance-snapshot.json
