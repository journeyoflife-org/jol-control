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

# The stale-copy NOTICE never changes the verdict, so an exit-code-only assertion passes
# with the detection still broken — which is exactly how S2-007 went unnoticed. These two
# assert on what the gate actually REPORTS.
assert_note() { # dir want_exit needle label
  out=$(python3 "$GATE" "$1" 2>&1); rc=$?
  if [ "$rc" != "$2" ]; then echo "  FAIL  $4 (exit=$rc want=$2)"; fail=$((fail+1)); return; fi
  if printf '%s' "$out" | grep -qF -- "$3"; then
    echo "  ok    $4 (exit=$rc, report names '$3')"; pass=$((pass+1));
  else echo "  FAIL  $4 (exit=$rc but the report never names '$3')"; fail=$((fail+1)); fi }
assert_no_note() { # dir want_exit needle label — guards against over-broad detection
  out=$(python3 "$GATE" "$1" 2>&1); rc=$?
  if [ "$rc" != "$2" ]; then echo "  FAIL  $4 (exit=$rc want=$2)"; fail=$((fail+1)); return; fi
  if printf '%s' "$out" | grep -qF -- "$3"; then
    echo "  FAIL  $4 (exit=$rc but the report DOES name '$3')"; fail=$((fail+1));
  else echo "  ok    $4 (exit=$rc, correctly silent about '$3')"; pass=$((pass+1)); fi }

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
# Single quotes are the point: this writes a Terraform template whose ${bucket} must survive to the file,
# not be expanded by the shell writing it.
# shellcheck disable=SC2016
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

# S2-007 regression fixtures. The filename shape is taken from the REAL artifact on the
# control-plane host: terraform.tfstate.backup_20260930_213529 (serial 301) was the only
# copy still recording github_team.security after live state (serial 306) dropped it, and
# `.suffix` on that name is ".backup_20260930_213529", so the old filter never saw the one
# copy that actually diverged. Contents are irrelevant here — only the NAME is detected.
tf "$W/stray_ts"; real_state "$W/stray_ts/terraform.tfstate"
: > "$W/stray_ts/terraform.tfstate.backup_20260930_213529"
# the plain form must keep being reported: a fix that only catches timestamps is not a fix
tf "$W/stray_plain"; real_state "$W/stray_plain/terraform.tfstate"
: > "$W/stray_plain/terraform.tfstate.backup"
# both shapes at once, so neither can mask the other in the count
tf "$W/stray_both"; real_state "$W/stray_both/terraform.tfstate"
: > "$W/stray_both/terraform.tfstate.backup"
: > "$W/stray_both/terraform.tfstate.backup_20260930_213529"
# over-broad-detection guard: workspace state is READ by Terraform and a lock file is
# transient. Neither is "a second answer to what exists", so neither may be reported.
tf "$W/nostray"; real_state "$W/nostray/terraform.tfstate"
mkdir -p "$W/nostray/terraform.tfstate.d/staging"
real_state "$W/nostray/terraform.tfstate.d/staging/terraform.tfstate"
: > "$W/nostray/.terraform.tfstate.lock.info"

# S1-011 regression: a directory holding MORE THAN ONE state file. Every other fixture has
# exactly one, so worst_state()'s per-file listing never ran — and it referenced an undefined
# module-global `root`, raising NameError that the handler reported as UNEVALUATED (exit 2).
# Two healthy states must yield a real verdict (exit 0) AND list both files.
mkdir -p "$W/multiws/terraform.tfstate.d/staging"
cp "$W/ws/main.tf" "$W/multiws/main.tf"
real_state "$W/multiws/terraform.tfstate"
real_state "$W/multiws/terraform.tfstate.d/staging/terraform.tfstate"
# ...and the worst-of-them rule must still hold: a healthy state beside a 0-byte one REFUSES
mkdir -p "$W/multiwsbad/terraform.tfstate.d/staging"
cp "$W/ws/main.tf" "$W/multiwsbad/main.tf"
real_state "$W/multiwsbad/terraform.tfstate"
: > "$W/multiwsbad/terraform.tfstate.d/staging/terraform.tfstate"

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
assert_note    "$W/stray_ts"    0 "terraform.tfstate.backup_20260930_213529" "NOTICE names a timestamped stale copy (S2-007)"
assert_note    "$W/stray_plain" 0 "terraform.tfstate.backup" "NOTICE still names the plain .backup form"
assert_note    "$W/stray_both"  0 "2 stale state cop(ies)" "NOTICE counts both shapes as two, not one"
assert_no_note "$W/nostray"     0 "stale state cop" "workspace state dir and lock file are not reported as strays"
assert_note    "$W/multiws"     0 "file   : terraform.tfstate -> ok" "multi-state dir gets a verdict, not UNEVALUATED (S1-011)"
assert_note    "$W/multiws"     0 "file   : terraform.tfstate.d/staging/terraform.tfstate -> ok" "and every state file in it is listed"
assert         "$W/multiwsbad"  1 "REFUSED worst-of-them: healthy state beside a 0-byte one"

echo "---"
echo "state-gate self-test: $((pass+fail)) tests, $fail failures"
[ "$fail" = 0 ] && { echo "PASSED — $pass state-gate tests, 0 failures."; exit 0; } || exit 1
