#!/bin/bash
# Self-tests for state_gate.py. Fixtures are rebuilt every run; the "ok" state document
# uses the key shape captured from a REAL terraform 1.16.1 state file
# (top-level: check_results/lineage/outputs/resources/serial/terraform_version/version;
#  resource entry: instances/mode/name/provider/type) — structure only, no values.
#   0 SAFE   1 REFUSED   2 UNEVALUATED — distinct on purpose (plan_gate.py convention).
set -u
# Default to the gate that lives in THIS repository, so the suite tests the versioned
# control and not whatever happens to be installed under /opt/jol/scripts.
GATE=${GATE:-"$(cd "$(dirname "$0")/.." && pwd)/scripts/state_gate.py"}
W=$(mktemp -d /tmp/state-gate-tests.XXXXXX)
trap 'rm -rf "$W"' EXIT
fail=0; pass=0

tf() { # dir  -> a config that declares 2 managed resources
  mkdir -p "$1"
  cat > "$1/main.tf" <<'T'
terraform { required_version = ">= 1.6" }
resource "github_repository" "a" { name = "a" }
resource "github_branch_protection" "b" { repository_id = "x" }
T
}
tf_only_terraform() { mkdir -p "$1"; printf 'terraform { required_version = ">= 1.6" }\n' > "$1/main.tf"; }
real_state() {
  printf '{"version":4,"terraform_version":"1.16.1","serial":7,"lineage":"eff08856-0000-0000-0000-000000000000","outputs":{},"resources":[{"mode":"managed","type":"github_repository","name":"a","provider":"provider[\\"registry.terraform.io/integrations/github\\"]","instances":[{"schema_version":1,"attributes":{"id":"a","name":"a"},"sensitive_attributes":[]}]}],"check_results":null}' > "$1"
}
assert() { # dir want label
  python3 "$GATE" "$1" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$2" ]; then echo "  ok    $3 (exit=$rc)"; pass=$((pass+1));
  else echo "  FAIL  $3 (exit=$rc want=$2)"; fail=$((fail+1)); fi }

# ok — state knows a managed resource
tf "$W/ok"; real_state "$W/ok/terraform.tfstate"
# zero-byte — the S10 case, and the one Terraform never produces itself
tf "$W/zero"; : > "$W/zero/terraform.tfstate"
# empty resources — valid JSON, no inventory (the apply.yml "120 to add" shape)
tf "$W/empty"; printf '{"version":4,"terraform_version":"1.16.1","serial":1,"lineage":"x","outputs":{},"resources":[]}\n' > "$W/empty/terraform.tfstate"
# missing state entirely
tf "$W/missing"
# garbage — truncated document, cannot be trusted
tf "$W/garbage"; printf '{"version":4,"terraform_ve' > "$W/garbage/terraform.tfstate"
# no managed resources declared -> nothing this config could create
tf_only_terraform "$W/noconfig"; : > "$W/noconfig/terraform.tfstate"
# remote-backend root: state lives in the backend, so the local file proves nothing.
# Must be UNEVALUATED (cannot-check), NEVER SAFE ("looks fine") and NEVER REFUSED
# ("something is broken") — the distinction is the whole point of exit code 2.
mkdir -p "$W/remote"
cat > "$W/remote/main.tf" <<'T'
terraform { backend "s3" { bucket = "jol-terraform-state-prod" key = "terraform.tfstate" } }
resource "aws_vpc" "this" { cidr_block = "10.0.0.0/16" }
T
# backend "local" is the opposite fact: the file IS the inventory, so no file = no state
mkdir -p "$W/localbe"
cat > "$W/localbe/main.tf" <<'T'
terraform { backend "local" {} }
resource "aws_vpc" "this" { cidr_block = "10.0.0.0/16" }
T
# backend supplied out-of-band through a rendered template (bootstrap's shape)
mkdir -p "$W/tplbe"
printf 'resource "aws_s3_bucket" "state" { bucket = "x" }\n' > "$W/tplbe/main.tf"
printf 'terraform {\n  backend "s3" {\n    bucket = "\${bucket}"\n  }\n}\n' > "$W/tplbe/backend.tpl"
# not a directory
printf 'x\n' > "$W/notadir"
# workspace-based LOCAL state (the real shape of jolarca bootstrap): the inventory lives
# in terraform.tfstate.d/<ws>/terraform.tfstate, NOT ./terraform.tfstate. A gate that only
# looks at the plain path calls live state "missing" — it did, on the first fleet sweep.
mkdir -p "$W/ws/terraform.tfstate.d/staging"
cat > "$W/ws/main.tf" <<'T'
resource "google_storage_bucket" "state" { name = "x" }
T
real_state "$W/ws/terraform.tfstate.d/staging/terraform.tfstate"
# same shape but truncated -> must still REFUSE
mkdir -p "$W/wszero/terraform.tfstate.d/staging"
cp "$W/ws/main.tf" "$W/wszero/main.tf"
: > "$W/wszero/terraform.tfstate.d/staging/terraform.tfstate"
# a child module that holds state of its own: the parent already manages these objects,
# so this file is a second inventory of the same real-world resources
mkdir -p "$W/tree2/modules/vpc" "$W/tree2/.git"
printf 'module "vpc" { source = "./modules/vpc" }\n' > "$W/tree2/main.tf"
printf 'resource "aws_vpc" "this" { cidr_block = "10.0.0.0/16" }\n' > "$W/tree2/modules/vpc/main.tf"
real_state "$W/tree2/modules/vpc/terraform.tfstate"
# child module: a parent in the SAME repo references it via a relative module source,
# and it legitimately holds no state. Positive evidence => exit 0. (Regression: an
# earlier revision returned exit 0 for ANY dir lacking state/tfvars/.terraform/backend,
# which also waved through "state lost"; that broke the missing-state fixture.)
mkdir -p "$W/tree/modules/vpc" "$W/tree/.git"
cat > "$W/tree/main.tf" <<'T'
module "vpc" { source = "./modules/vpc" }
T
cat > "$W/tree/modules/vpc/main.tf" <<'T'
resource "aws_vpc" "this" { cidr_block = "10.0.0.0/16" }
T
# vendored copy of third-party code: not ours, never an apply target here
mkdir -p "$W/ven/.external_modules/github.com/terraform-aws-modules/terraform-aws-vpc/abc123"
printf 'resource "aws_vpc" "this" { cidr_block = "10.0.0.0/16" }\n' \
  > "$W/ven/.external_modules/github.com/terraform-aws-modules/terraform-aws-vpc/abc123/main.tf"
# root that only calls modules, no state: a module block still CREATES resources,
# so an empty state here is exactly as dangerous as a bare resource block
mkdir -p "$W/modonly"
printf 'module "vpc" { source = "./modules/vpc" }\n' > "$W/modonly/main.tf"

assert "$W/ok"      0 "SAFE   state accounts for managed resources"
assert "$W/zero"    1 "REFUSED 0-byte state"
assert "$W/empty"   1 "REFUSED state parses but has zero resources"
assert "$W/missing" 1 "REFUSED no state while config declares resources"
assert "$W/garbage" 2 "UNEVALUATED state does not parse"
assert "$W/noconfig" 0 "SAFE   config declares no managed resources"
assert "$W/notadir" 2 "UNEVALUATED path is not a directory"
assert "$W/remote"    2 "UNEVALUATED remote backend: local state proves nothing"
assert "$W/localbe"   1 "REFUSED backend \"local\" with no state file"
assert "$W/tplbe"     2 "UNEVALUATED backend via -backend-config template"
assert "$W/tree/modules/vpc" 0 "SAFE   child module referenced by a parent"
assert "$W/ven/.external_modules/github.com/terraform-aws-modules/terraform-aws-vpc/abc123" 0 "SAFE   vendored third-party copy"
assert "$W/modonly" 1 "REFUSED module-only root with no state"
assert "$W/ws"      0 "SAFE   workspace state under terraform.tfstate.d/"
assert "$W/wszero"  1 "REFUSED 0-byte workspace state"
assert "$W/tree2/modules/vpc" 1 "REFUSED child module holding its own state"

echo "---"
echo "state-gate self-test: $((pass+fail)) tests, $fail failures"
[ "$fail" = 0 ] && { echo "PASSED — $pass state-gate tests, 0 failures."; exit 0; } || exit 1
