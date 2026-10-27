#!/usr/bin/env bash
# RB-08 create-backup. Exit codes follow this repository's gate convention:
#   0 = written AND both custody paths proven   1 = refused, nothing kept
#   2 = written but a control could not be checked - NOT a pass
set -euo pipefail
umask 077        # verification writes PLAINTEXT state; this host's default umask is 0002

REPO="${REPO:-/opt/jol/repos/jol-control}"
SRC="${SRC:-$REPO/terraform.tfstate}"
DEST="${DEST:?DEST is required - a directory on a different block device}"
HOST_KEY="${HOST_KEY:-$HOME/.config/age/state-backup-key.txt}"
RECOVERY_KEY="${RECOVERY_KEY:-}"; RECOVERY_PUB="${RECOVERY_PUB:-}"
OUT=""; KEEP=0; CREATED=0; RC=0; TMP=()
# ONE exit trap. `trap ... RETURN` inside a function does not fire when that function calls
# `exit`, and does not fire when `set -e` aborts mid-function - both failure paths used to leak
# a temp file holding decrypted state. It also drops the artefact unless the run fully succeeded,
# so a rejected backup cannot sit on the backup disk looking like a snapshot - but ONLY a file
# this run created. Without CREATED, a refused same-second re-run deleted the ORIGINAL backup.
# shellcheck disable=SC2317  # invoked indirectly via `trap cleanup EXIT`; shellcheck cannot follow it
cleanup(){ local p; for p in "${TMP[@]:-}"; do if [ -n "$p" ]; then rm -f "$p"; fi; done
           if [ "$KEEP" != 1 ] && [ "$CREATED" = 1 ]; then rm -f "${OUT:-}" "${OUT:-}.info"; fi; }
trap cleanup EXIT

[ -n "$RECOVERY_KEY" ] || [ -n "$RECOVERY_PUB" ] || {
  echo "FAIL: set RECOVERY_KEY (identity file - verifies the off-host path) or";
  echo "      RECOVERY_PUB (age1... - records it but cannot verify it)."; exit 1; }
[ -s "$SRC" ] || { echo "FAIL: source missing or 0 bytes: $SRC"; exit 1; }
# Validate shape AND content before writing. A document whose `resources` array is EMPTY is a
# perfectly valid state - it is exactly what this host produced when the inventory was destroyed
# (S2-012) - so `has("resources")` alone would certify a wiped state as a good backup.
jq -e '(.terraform_version|type=="string") and (.lineage|type=="string")
       and (.serial|type=="number") and ((.resources|length) > 0)' "$SRC" >/dev/null 2>&1 || {
  echo "FAIL: $SRC is not a populated Terraform state document.";
  echo "      Needs terraform_version, lineage, a numeric serial and at least one resource."; exit 1; }
if [ ! -d "$DEST" ] || [ ! -w "$DEST" ]; then
  echo "FAIL: DEST absent or not writable: $DEST"; exit 1; fi
# Confirmed BEFORE any encryption: a run that cannot reach the inventory check must not write a
# backup it then has to disown. Order matters - verifying after the fact still leaves the operator
# holding a file whose status is unknown.
if [ ! -f "$REPO/scripts/state_gate.py" ]; then
  echo "FAIL: $REPO/scripts/state_gate.py not found - the inventory check cannot run.";
  echo "      Do not report this backup as verified."; exit 2; fi
DEST_ABS="$(cd "$DEST" && pwd -P)"
case "$DEST_ABS" in
  "$REPO"|"$REPO"/*) echo "FAIL: DEST is inside the repository ($DEST_ABS). Ciphertext - and on a"
                     echo "      hard failure its plaintext sibling - must never land in a git tree."; exit 1;;
esac

HOST_PUB="$(age-keygen -y "$HOST_KEY")"
if [ -n "$RECOVERY_KEY" ]; then RECOVERY_PUB="$(age-keygen -y "$RECOVERY_KEY")"; fi
# Compares two recipient STRINGS. That detects "you passed the same key twice". It does not prove,
# and cannot prove, where either key is held.
[ "$HOST_PUB" != "$RECOVERY_PUB" ] || {
  echo "FAIL: the recovery recipient equals HOST_KEY ($HOST_PUB).";
  echo "      One custody path wearing two labels survives nothing the host does not."; exit 1; }

EXPECT_MD5="$(md5sum "$SRC" | awk '{print $1}')"
EMPTY_MD5="$(printf '' | md5sum | awk '{print $1}')"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
# Deliberately the same basename convention as /opt/jol/backup/tfstate/, so the Restore half
# below can actually find what this half writes.
OUT="$DEST_ABS/jol-control-terraform.tfstate.$STAMP.age"
# Reserve the name atomically: `age -o` overwrites an existing file without warning, and a
# second-granularity stamp means two runs in one second collide.
set -C
if ! : > "$OUT" 2>/dev/null; then set +C
  echo "FAIL: $OUT already exists - refusing to overwrite an existing backup"; exit 1; fi
set +C
CREATED=1   # from here the trap may clean this path; before here the file is not ours to remove

age --encrypt --recipient "$HOST_PUB" --recipient "$RECOVERY_PUB" --output "$OUT" "$SRC"
chmod 600 "$OUT"
echo "written   : $OUT ($(stat -c%s "$OUT") bytes)"
echo "recipients: $HOST_PUB  $RECOVERY_PUB"

verify() {  # label, identity-file
  local t m; t="$(mktemp)"; TMP+=("$t")
  age --decrypt -i "$2" "$OUT" > "$t"
  m="$(md5sum "$t" | awk '{print $1}')"
  if [ "$m" = "$EMPTY_MD5" ]; then echo "FAIL [$1]: decrypted to ZERO BYTES - nothing was read"; exit 1; fi
  if [ "$m" != "$EXPECT_MD5" ]; then echo "FAIL [$1]: md5 $m != source $EXPECT_MD5"; exit 1; fi
  echo "PASS [$1]: a distinct identity opens this file and reproduces the source md5 $m"
}
verify host-key "$HOST_KEY"
if [ -n "$RECOVERY_KEY" ]; then
  verify recovery-key "$RECOVERY_KEY"
else
  RC=2   # deliberately not 0: an unproven control must not report success
  echo "NOT VERIFIED [recovery-key]: only the recipient was supplied, so the off-host path is"
  echo "                 recorded in the header but not proven to open this file. Prove it by"
  echo "                 decrypting on the machine that holds the identity."
fi

DEC="$OUT.decoded"; TMP+=("$DEC")
age --decrypt -i "$HOST_KEY" "$OUT" > "$DEC"
# The config directory is PINNED, not inherited. `state_gate.py` takes `dir` positionally with
# default `.`, so calling it with only --state judges the backup against whatever directory the
# operator happens to be standing in - measured from /tmp it answered `SAFE` over ZERO resource
# blocks. A vacuous pass, not an honest refusal.
set +e; python3 "$REPO/scripts/state_gate.py" "$REPO" --state "$DEC" | sed 's/^/    /'
G=${PIPESTATUS[0]}; set -e
if [ "$G" -ne 0 ]; then echo "FAIL [state-gate]: exit $G - refusing to certify this backup"; exit 1; fi

# Persist the facts the Restore half demands ("a checksum of the state you expect"). Without this
# file those numbers exist only on a terminal scrollback.
{ echo "serial    : $(jq -r '.serial' "$SRC")"
  echo "lineage   : $(jq -r '.lineage' "$SRC")"
  echo "resources : $(jq '.resources|length' "$SRC")"
  echo "instances : $(jq '[.resources[].instances[]]|length' "$SRC")"
  echo "md5       : $EXPECT_MD5"
  echo "created   : $STAMP"
  echo "recipients: $HOST_PUB $RECOVERY_PUB"
  echo "off-host-verified: $([ "$RC" = 0 ] && echo yes || echo no)"
} > "$OUT.info"; chmod 600 "$OUT.info"
KEEP=1
echo "OK: backup written and readable; recovery path status stated above (exit 2 = not verified)"
exit "$RC"
