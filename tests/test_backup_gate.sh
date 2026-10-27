#!/usr/bin/env bash
# tests/test_backup_gate.sh — self-tests for scripts/backup_state.sh (runbooks.md RB-08).
#
# Why this file exists: the backup script lived only as a fenced block in a runbook, its
# verification was reproducible only from one operator's terminal, and two of its worst defects
# (a plaintext-state leak on the failure path, and a `state-gate` call that passed vacuously)
# were found by reading, not by running. A script with no committed test can rot silently.
#
# Exit codes follow the repository's gate convention:
#   0  every case that COULD run passed
#   1  a case failed — the script does not do what the runbook claims
#   2  UNEVALUATED: the guard cases could not run at all. Never reported as a pass.
#
# The guard cases need only `jq`, so they run in CI. The crypto cases also need `age` and an
# identity; where those are absent they are counted as SKIPPED and announced, never as passes.
# Nothing here writes inside the repository: every artefact goes to one temp directory that a
# trap removes, because this script's subject matter is a file that must never land in a git tree.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO/scripts/backup_state.sh"
[ -f "$GATE" ] || { echo "UNEVALUATED — $GATE not found"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "UNEVALUATED — jq unavailable, guard cases cannot run"; exit 2; }

W="$(mktemp -d)"
chmod 700 "$W"
trap 'find "$W" -type f -delete 2>/dev/null; rm -rf "$W" 2>/dev/null' EXIT
mkdir -p "$W/dest" "$W/bin" "$W/norepo"

# Pin the output name so the collision case is deterministic rather than timing-dependent.
printf '#!/bin/sh\necho 19700101T000000Z\n' > "$W/bin/date"
chmod +x "$W/bin/date"

# Fixtures built from the shape of a real Terraform 1.16.1 state document.
REAL_STATE="$REPO/terraform.tfstate"
SYNTH="$W/state.json"
jq -n '{terraform_version:"1.16.1",serial:306,lineage:"test-lineage-0000",
        resources:[{type:"github_repository",name:"repo",
                    instances:[{index_key:"x",attributes:{name:"x"}}]}]}' > "$SYNTH"
WIPED="$W/wiped.json"
jq -n '{terraform_version:"1.16.1",serial:1,lineage:"x",resources:[]}' > "$WIPED"

pass=0; fail=0; skip=0

# run <expect-rc> <label> <dest> <max-files-left> [VAR=value ...]
run() {
  local want="$1" label="$2" dest="$3" maxart="$4"; shift 4
  local rc n leak verdict
  find "$dest" -type f -delete 2>/dev/null
  # `env` because a VAR=value that arrives via expansion is parsed as a COMMAND name, not an
  # assignment — that harness bug produced five fake failures in this script's own development.
  timeout 120 env PATH="$W/bin:$PATH" DEST="$dest" "$@" "$GATE" </dev/null >"$W/out" 2>&1
  rc=$?
  n=$(find "$dest" -type f 2>/dev/null | wc -l)
  leak=$(find "$dest" -name '*.decoded' -type f 2>/dev/null)
  verdict=no-verdict
  grep -qE 'PASS|NOT VERIFIED|FAIL:|OK:|DEST is required' "$W/out" && verdict=ok
  if [ "$rc" = "$want" ] && [ "$n" -le "$maxart" ] && [ -z "$leak" ] && [ "$verdict" = ok ]; then
    pass=$((pass+1)); printf '  ok    %-46s RC=%-2s files=%s\n' "$label" "$rc" "$n"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s RC=%s want=%s files=%s max=%s verdict=%s\n' \
      "$label" "$rc" "$want" "$n" "$maxart" "$verdict"
    sed -n '1,3p' "$W/out" | sed 's/^/          /'
  fi
}

echo "backup_state.sh self-test"
echo
echo "guard paths (jq only — these run anywhere):"
# DEST unset must be refused *before* the helper can supply it, so this one bypasses run().
if timeout 60 env PATH="$W/bin:$PATH" RECOVERY_KEY=x "$GATE" </dev/null >"$W/o" 2>&1; then
  fail=$((fail+1)); printf '  FAIL  %-46s it accepted a missing DEST\n' "1 DEST unset"
elif grep -q 'DEST' "$W/o"; then
  pass=$((pass+1)); printf '  ok    %-46s RC=non-zero, names DEST\n' "1 DEST unset"
else
  fail=$((fail+1)); printf '  FAIL  %-46s refused but did not say why\n' "1 DEST unset"
  sed -n '1,3p' "$W/o" | sed 's/^/          /'
fi
run 1 "2 neither RECOVERY_KEY nor RECOVERY_PUB"   "$W/dest" 0 RECOVERY_KEY="" RECOVERY_PUB=""
run 1 "3 destination absent"                      "$W/absent" 0 RECOVERY_KEY=x
run 1 "4 destination inside the repository"       "$W/dest" 0 DEST="." RECOVERY_KEY=x
run 1 "5 SRC is not JSON"                         "$W/dest" 0 SRC="$REPO/Makefile" RECOVERY_KEY=x
run 1 "6 SRC is valid JSON but not a state doc"   "$W/dest" 0 SRC="$REPO/tests/fixtures/plan_gate/clean.json" RECOVERY_KEY=x
run 1 "7 SRC is a WIPED state (resources: [])"    "$W/dest" 0 SRC="$WIPED" RECOVERY_KEY=x
run 1 "8 SRC is 0 bytes"                          "$W/dest" 0 SRC=/dev/null RECOVERY_KEY=x
# Case 9 exercises the pinned-config fix. With REPO pointed at a tree that has no
# scripts/state_gate.py the run must refuse to certify (exit 2) and clean up after itself.
run 2 "9 state-gate unreachable -> not certified" "$W/dest" 0 REPO="$W/norepo" SRC="$SYNTH" RECOVERY_KEY=x

# Crypto paths need age, two identities, and a state file the pinned `state-gate` call can judge
# against this repository's own config. A synthetic 1-resource state would be REFUSED as incomplete,
# so the full path is only meaningful against the real inventory - which a CI runner does not have
# (terraform.tfstate is gitignored). Skip honestly rather than assert something untrue.
if command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1 && [ -s "$REAL_STATE" ]; then
  echo
  echo "crypto paths (age + a real state present):"
  umask 077
  age-keygen -o "$W/host.txt" </dev/null >/dev/null 2>&1
  age-keygen -o "$W/recovery.txt" </dev/null >/dev/null 2>&1
  HPUB=$(age-keygen -y "$W/host.txt" </dev/null 2>&1)
  RPUB=$(age-keygen -y "$W/recovery.txt" </dev/null 2>&1)
  # The script defaults HOST_KEY to the operator's file; point it at the throwaway instead.
  K="HOST_KEY=$W/host.txt"
  run 1 "10 recovery identity equals the host's"  "$W/dest" 0 "$K" RECOVERY_KEY="$W/host.txt"
  run 1 "11 recovery recipient equals the host's" "$W/dest" 0 "$K" RECOVERY_PUB="$HPUB"
  run 0 "12 distinct identity -> both paths proven" "$W/dest" 2 "$K" RECOVERY_KEY="$W/recovery.txt"
  run 2 "13 recipient only -> NOT VERIFIED, RC=2"   "$W/dest" 2 "$K" RECOVERY_PUB="$RPUB"
  # A refused same-second re-run must NOT remove the snapshot that was already there.
  find "$W/dest" -type f -delete 2>/dev/null
  timeout 120 env PATH="$W/bin:$PATH" DEST="$W/dest" HOST_KEY="$W/host.txt" RECOVERY_KEY="$W/recovery.txt" \
    "$GATE" </dev/null >"$W/o" 2>&1
  before=$(sha256sum "$W/dest"/*.age 2>/dev/null | cut -d' ' -f1)
  bcount=$(find "$W/dest" -type f | wc -l)
  modes=$(stat -c'%a' "$W/dest"/* 2>/dev/null | paste -sd, -)
  timeout 120 env PATH="$W/bin:$PATH" DEST="$W/dest" HOST_KEY="$W/host.txt" RECOVERY_KEY="$W/recovery.txt" \
    "$GATE" </dev/null >"$W/o" 2>&1
  rc=$?
  after=$(sha256sum "$W/dest"/*.age 2>/dev/null | cut -d' ' -f1)
  acount=$(find "$W/dest" -type f | wc -l)
  if [ "$rc" = 1 ] && [ -n "$before" ] && [ "$before" = "$after" ] && [ "$bcount" = "$acount" ]; then
    pass=$((pass+1)); printf '  ok    %-46s RC=1, original preserved (%s files)\n' \
      "14 collision refuses without deleting" "$acount"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s RC=%s before=%s after=%s files %s->%s\n' \
      "14 collision refuses without deleting" "$rc" "${before:0:8}" "${after:0:8}" "$bcount" "$acount"
  fi
  if [ "$modes" = "600,600" ]; then
    pass=$((pass+1)); printf '  ok    %-46s modes=%s\n' "15 artefacts are owner-only" "$modes"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s modes=%s (want 600,600)\n' "15 artefacts are owner-only" "$modes"
  fi
  if grep -q 'instances : 1' "$W/dest"/*.info 2>/dev/null && grep -q 'off-host-verified: yes' "$W/dest"/*.info 2>/dev/null; then
    pass=$((pass+1)); printf '  ok    %-46s\n' "16 .info sidecar records serial/instances/custody"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s\n' "16 .info sidecar records serial/instances/custody"
    sed -n '1,8p' "$W/dest"/*.info 2>/dev/null | sed 's/^/          /'
  fi
  # The leak that started this: no plaintext may survive outside the encrypted artefact.
  if [ -n "$(find "$W" -name '*.decoded' -type f 2>/dev/null)" ]; then
    fail=$((fail+1)); printf '  FAIL  %-46s\n' "17 no plaintext state left in the work area"
  else
    pass=$((pass+1)); printf '  ok    %-46s\n' "17 no plaintext state left in the work area"
  fi
else
  skip=8
  echo
  echo "crypto paths: SKIPPED - needs age, age-keygen and a real $REAL_STATE."
  echo "          $skip cases were NOT evaluated. A skipped case is not a pass: on a host with age"
  echo "          but no state, encryption, cleanup and the collision guarantee go unproven."
fi

# The script must never write into the repository it is protecting.
if git -C "$REPO" status --porcelain -uall 2>/dev/null | grep -qiE '\.age|\.decoded'; then
  fail=$((fail+1)); echo "  FAIL  18 no backup artefact in the working tree"
else
  pass=$((pass+1)); echo "  ok    18 no backup artefact in the working tree"
fi

# The runbook reproduces this script verbatim. If the fenced block and the file drift, the document
# describes code that does not exist - which is how "fail-closed" came to describe a plaintext leak.
if [ -f "$REPO/docs/runbooks.md" ] && command -v python3 >/dev/null 2>&1; then
  # NOTE: no `</dev/null` on this command. The heredoc IS stdin; adding a later stdin redirect makes
  # `python3 -` read its PROGRAM from /dev/null, so it runs nothing and exits 0 - a case that reports
  # pass forever. Caught by appending one newline to the script and watching this case not notice.
  # And the opposite failure mode, caught only because the BASELINE went red first: this body once
  # read `s==="```"`, a Python SyntaxError, so the case exited 1 and blamed drift for a typo. A test
  # that always fails is as useless as one that always passes, and looks more convincing.
  if python3 - "$REPO" "$GATE" <<'PY' >"$W/c19.err" 2>&1
import pathlib,sys,re
repo=pathlib.Path(sys.argv[1]); gate=pathlib.Path(sys.argv[2])
b=[]; cur=None
for ln in (repo/"docs/runbooks.md").read_text().splitlines():
    s=ln.strip()
    if s.startswith("```bash") and cur is None: cur=[]; continue
    if s == "```" and cur is not None: b.append("\n".join(cur)); cur=None; continue
    if cur is not None: cur.append(re.sub(r"^ {0,3}","",ln))
sel=[x for x in b if "RB-08 create-backup" in x]
assert len(sel)==1, f"expected exactly one RB-08 fence, found {len(sel)}"
sys.exit(0 if sel[0]+"\n" == gate.read_text() else 1)
PY
  then
    pass=$((pass+1)); echo "  ok    19 runbook fence is byte-identical to the script"
  else
    fail=$((fail+1)); echo "  FAIL  19 runbook fence has drifted from scripts/backup_state.sh"
    # Distinguish a real difference from a broken checker: SyntaxError/AssertionError must not be
    # reported as drift, or the harness failure impersonates a finding about the document.
    if grep -qE 'SyntaxError|Traceback|AssertionError' "$W/c19.err" 2>/dev/null; then
      echo "          NOT drift - the checker itself errored:"; sed -n '1,3p' "$W/c19.err" | sed 's/^/            /'
    else
      echo "          Re-extract the fence from docs/runbooks.md into the script, or fix the document."
      sed -n '1,3p' "$W/c19.err" | sed 's/^/            /'
    fi
  fi
else
  skip=$((skip+1)); echo "  SKIP  19 fence/script identity (needs docs/runbooks.md + python3)"
fi

# `umask 077` cannot be pinned behaviourally: the temp files are mktemp-created (0600) and the EXIT
# trap removes the decrypted copy, so a run WITHOUT the umask still leaves nothing observable behind -
# it merely widens the window in which plaintext state exists at 0664. Mutation testing proved the
# suite does not detect its removal. So the line is asserted directly, as a source-level invariant.
if grep -qE '^umask 077' "$GATE"; then
  pass=$((pass+1)); echo "  ok    20 script sets umask 077 before any redirect"
else
  fail=$((fail+1)); echo "  FAIL  20 script no longer sets umask 077 - plaintext state would be group-writable"
fi

echo "---"
echo "backup-gate self-test: $pass passed, $fail failed, $skip skipped"
if [ "$fail" -gt 0 ]; then echo "FAILED — $fail backup-gate violation(s)"; exit 1; fi
if [ "$pass" -lt 12 ]; then
  # 12 is the measured census of cases that need neither age nor a real state: cases 1-9, 18, 19
  # and 20. Measured, not assumed - a threshold guessed below the true count turns a broken suite
  # green, and guessed above it makes every CI run red, which is the S1-012 failure mode again.
  echo "UNEVALUATED — only $pass cases ran; the guard set is incomplete, this is not a pass"; exit 2
fi
if [ "$skip" -gt 0 ] && [ "$pass" -lt 12 ]; then
  echo "UNEVALUATED — $skip cases skipped and only $pass ran; not a pass"; exit 2
fi
echo "PASSED — $pass backup-gate tests, 0 failures$([ "$skip" -gt 0 ] && echo " ($skip crypto cases skipped)")."
exit 0
