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

# The script resolves the PHYSICAL DISK behind SRC and DEST (findmnt --target, then lsblk PKNAME).
# The suite's work area and the live state are on the same disk, so without a stub every backup case
# would be refused for a reason that has nothing to do with what is under test. These pretend the
# destination is on a second disk; cases 21 and 22 then exercise the refusal and the unresolvable
# branch explicitly, so the check itself is still tested rather than bypassed.
cat > "$W/bin/findmnt" <<'STUB'
#!/bin/sh
# Called as: findmnt -no SOURCE --target <path>
# Anything under /opt/jol is the state's real disk; the suite's temp destination is reported as a
# second disk so the backup cases can run at all. Cases 21-23 exercise the refusal and the
# unresolvable branch against their own stub directories, so the check is tested, not bypassed.
for a in "$@"; do case "$a" in /opt/jol/*) echo /dev/nvme0n1p8; exit 0;; esac; done
echo /dev/sdb1
STUB
cat > "$W/bin/lsblk" <<'STUB'
#!/bin/sh
# Called as: lsblk -no PKNAME <device>. Scan every argument, not $1: $1 is "-no", and a stub that
# looked only at $1 returned nothing for every device, which silently disabled the device check and
# let the same-disk case "pass" on an unrelated error. Take the last argument, which is the device.
for a in "$@"; do dev="$a"; done
case "$dev" in
  /dev/nvme0n1p8) echo nvme0n1 ;;
  /dev/sdb1)      echo sdb ;;
esac
STUB
chmod +x "$W/bin/findmnt" "$W/bin/lsblk"
mkdir -p "$W/binsame"
sed 's/echo sdb/echo nvme0n1/' "$W/bin/lsblk" > "$W/binsame/lsblk"
cp "$W/bin/findmnt" "$W/bin/date" "$W/binsame/" 2>/dev/null; chmod +x "$W/binsame"/*

# Fixtures built from the shape of a real Terraform 1.16.1 state document.
REAL_STATE="$REPO/terraform.tfstate"
SYNTH="$W/state.json"
jq -n '{terraform_version:"1.16.1",serial:306,lineage:"test-lineage-0000",
        resources:[{type:"github_repository",name:"repo",
                    instances:[{index_key:"x",attributes:{name:"x"}}]}]}' > "$SYNTH"
WIPED="$W/wiped.json"
jq -n '{terraform_version:"1.16.1",serial:1,lineage:"x",resources:[]}' > "$WIPED"

pass=0; fail=0; skip=0

# run <expect-rc> <label> <dest> <max-files-left> <must-say> [VAR=value ...]
#
# `must-say` is not decoration. Every guard case supplies a deliberately invalid RECOVERY_KEY, so ANY
# later failure also produces the expected exit code 1 — a suite comparing only exit codes reports a
# pass for the wrong reason. That is precisely how case 7 stayed green after the wiped-state guard was
# deleted out from under it: the stubbed device check refused, RC=1 matched, and nothing noticed. Each
# case now asserts the words that identify ITS own refusal.
run() {
  local want="$1" label="$2" dest="$3" maxart="$4" says="$5"; shift 5
  local rc n leak verdict
  find "$dest" -type f -delete 2>/dev/null
  # `env` because a VAR=value that arrives via expansion is parsed as a COMMAND name, not an
  # assignment — that harness bug produced five fake failures in this script's own development.
  timeout 120 env PATH="$W/bin:$PATH" DEST="$dest" "$@" "$GATE" </dev/null >"$W/out" 2>&1
  rc=$?
  n=$(find "$dest" -type f 2>/dev/null | wc -l)
  leak=$(find "$dest" -name '*.decoded' -type f 2>/dev/null)
  verdict=said-it
  grep -qF -- "$says" "$W/out" || verdict=missing-expected-text
  # Ordering assertion, and the one that actually closes the vacuous pass: every guard case supplies a
  # deliberately bogus RECOVERY_KEY, so if `age` was reached at all, the guard being tested let the run
  # continue. Asserting the refusal text is not enough on its own — with the refusal's `exit 1` deleted
  # the text is still printed, the age error still yields RC=1, and the case still "passes".
  if grep -qE 'age-keygen: error|^age: error|age: failed' "$W/out"; then
    verdict="reached the crypto stage - an earlier guard did not stop it"
  fi
  # And the sharper version of the same idea: the refusal must come from THIS guard. Delete only the
  # in-repo refusal's `exit 1` and the next guard stops the run instead - no age error, the expected
  # text is still printed, RC still 1, and the case would pass while testing a different control. So
  # every FAIL line in the output has to carry the phrase this case is about.
  if [ "$verdict" = said-it ]; then
    local nf nfe; nf=$(grep -c '^FAIL:' "$W/out"); nfe=$(grep '^FAIL:' "$W/out" | grep -cF -- "$says")
    if [ "$nf" -gt 0 ] && [ "$nf" -ne "$nfe" ]; then
      verdict="a DIFFERENT guard stopped it ($nf refusals, only $nfe about this one)"
    fi
  fi
  if [ "$rc" = "$want" ] && [ "$n" -le "$maxart" ] && [ -z "$leak" ] && [ "$verdict" = said-it ]; then
    pass=$((pass+1)); printf '  ok    %-46s RC=%-2s files=%s\n' "$label" "$rc" "$n"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s RC=%s want=%s files=%s max=%s leak=[%s] %s\n' \
      "$label" "$rc" "$want" "$n" "$maxart" "$leak" "$verdict"
    printf '          needed the words: %s\n' "$says"
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
run 1 "2 neither RECOVERY_KEY nor RECOVERY_PUB"   "$W/dest" 0 "set RECOVERY_KEY" RECOVERY_KEY="" RECOVERY_PUB=""
run 1 "3 destination absent"                      "$W/absent" 0 "DEST absent or not writable" RECOVERY_KEY=x
run 1 "4 destination inside the repository"       "$W/dest" 0 "DEST is inside the repository" DEST="." RECOVERY_KEY=x
run 1 "5 SRC is not JSON"                         "$W/dest" 0 "not a populated Terraform state document" SRC="$REPO/Makefile" RECOVERY_KEY=x
run 1 "6 SRC is valid JSON but not a state doc"   "$W/dest" 0 "not a populated Terraform state document" SRC="$REPO/tests/fixtures/plan_gate/clean.json" RECOVERY_KEY=x
run 1 "7 SRC is a WIPED state (resources: [])"    "$W/dest" 0 "not a populated Terraform state document" SRC="$WIPED" RECOVERY_KEY=x
run 1 "8 SRC is 0 bytes"                          "$W/dest" 0 "source missing or 0 bytes" SRC=/dev/null RECOVERY_KEY=x
# Case 9 exercises the pinned-config fix. With REPO pointed at a tree that has no
# scripts/state_gate.py the run must refuse to certify (exit 2) and clean up after itself.
run 2 "9 state-gate unreachable -> not certified" "$W/dest" 0 "state_gate.py not found" REPO="$W/norepo" SRC="$SYNTH" RECOVERY_KEY=x
# 21-23: the device check. Refused when both paths resolve to one disk, and warned-about (never
# silently passed) when the disk cannot be resolved at all. The stub directory that maps sdb1 to
# nvme0n1 reproduces exactly the layout this host had before RB-08 existed. Numbered past 20 so the
# crypto block keeps its own labels. These cannot use the generic run() helper, which pins the
# different-disk stub; the refusal needs its own PATH.
if PATH="$W/binsame:$W/bin:$PATH" timeout 60 env DEST="$W/dest" RECOVERY_KEY=x "$GATE" </dev/null >"$W/o" 2>&1; then
  fail=$((fail+1)); printf '  FAIL  %-46s accepted a same-disk destination\n' "21 refusal names the disk"
elif grep -q 'SAME physical disk' "$W/o"; then
  pass=$((pass+1)); printf '  ok    %-46s RC=1 and names the disk\n' "21 refusal names the disk"
else
  fail=$((fail+1)); printf '  FAIL  %-46s refused, but not for the disk\n' "21 refusal names the disk"
  sed -n '1,4p' "$W/o" | sed 's/^/          /'
fi
if grep -q 'UNVERIFIED' "$W/o"; then
  fail=$((fail+1)); printf '  FAIL  %-46s the stubs are not resolving, so case 21 is unproven\n' "21 stub integrity"
else
  pass=$((pass+1)); printf '  ok    %-46s (stubs resolved)\n' "21 stub integrity"
fi
# An empty lsblk answer must produce a WARN plus an "unevaluated" sidecar entry, never a claim of
# off-device protection. It still exits non-zero here because the fake key fails afterwards, which
# is fine: the assertion is about the wording, not the code.
mkdir -p "$W/binvoid"; printf '#!/bin/sh\n' > "$W/binvoid/lsblk"; chmod +x "$W/binvoid/lsblk"
cp "$W/bin/findmnt" "$W/bin/date" "$W/binvoid/" 2>/dev/null; chmod +x "$W/binvoid"/*
PATH="$W/binvoid:$W/bin:$PATH" timeout 60 env DEST="$W/dest" RECOVERY_KEY=x "$GATE" </dev/null >"$W/o" 2>&1
if grep -q 'UNVERIFIED' "$W/o" && grep -q 'could not be resolved' "$W/o"; then
  pass=$((pass+1)); printf '  ok    %-46s (it refuses to claim it)\n' "23 unresolvable disk is not a pass"
else
  fail=$((fail+1)); printf '  FAIL  %-46s\n' "23 unresolvable disk is not a pass"
  sed -n '1,4p' "$W/o" | sed 's/^/          /'
fi

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
  run 1 "10 recovery identity equals the host's"  "$W/dest" 0 "recovery recipient equals HOST_KEY" "$K" RECOVERY_KEY="$W/host.txt"
  run 1 "11 recovery recipient equals the host's" "$W/dest" 0 "recovery recipient equals HOST_KEY" "$K" RECOVERY_PUB="$HPUB"
  run 0 "12 distinct identity -> both paths proven" "$W/dest" 2 "OK: backup written" "$K" RECOVERY_KEY="$W/recovery.txt"
  run 2 "13 recipient only -> NOT VERIFIED, RC=2"   "$W/dest" 2 "NOT VERIFIED [recovery-key]" "$K" RECOVERY_PUB="$RPUB"
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
  if grep -q 'instances : 1' "$W/dest"/*.info 2>/dev/null && grep -q 'recovery-key-decrypted: yes' "$W/dest"/*.info 2>/dev/null \
     && grep -q 'recovery-key-location : NOT CHECKED' "$W/dest"/*.info 2>/dev/null \
     && grep -q 'device-check          : verified-different' "$W/dest"/*.info 2>/dev/null; then
    pass=$((pass+1)); printf '  ok    %-46s\n' "16 sidecar states what was proven AND what was not"
  else
    fail=$((fail+1)); printf '  FAIL  %-46s\n' "16 sidecar states what was proven AND what was not"
    sed -n '1,10p' "$W/dest"/*.info 2>/dev/null | sed 's/^/          /'
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

# ---------------------------------------------------------------------------
# scripts/state_backup_guard.sh - the scheduled front door (runbooks.md RB-09).
#
# The property worth testing is that a timer cannot report success for a backup it was not allowed to
# make: no recipient means UNEVALUATED (2), an unmounted destination means refusal (1) and nothing
# written, and a snapshot young enough means the job does nothing at all. A `logger` shim keeps the
# runs out of the real journal.
# ---------------------------------------------------------------------------
GUARD="$REPO/scripts/state_backup_guard.sh"
if [ -f "$GUARD" ]; then
  echo
  echo "scheduled-refresh guard (needs jq only):"
  mkdir -p "$W/nolog"; printf '#!/bin/sh\nexit 0\n' > "$W/nolog/logger"; chmod +x "$W/nolog/logger"
  REC="$W/recipient.txt"; GD="$W/guarddest"
  g() { # expect-rc label [VAR=..]...
    local want="$1" label="$2"; shift 2; local rc
    # Deliberately WITHOUT $W/bin: that directory holds a stub `date` for the backup cases, and putting
    # it on the guard's PATH made `date +%s` non-numeric and crashed the arithmetic. Case 33 asserts
    # that the same input now yields UNEVALUATED rather than a shell error.
    timeout 120 env PATH="$W/nolog:/usr/bin:/bin" "$@" bash "$GUARD" </dev/null >"$W/go" 2>&1
    rc=$?
    if [ "$rc" = "$want" ]; then pass=$((pass+1)); printf '  ok    %-46s RC=%s\n' "$label" "$rc"
    else fail=$((fail+1)); printf '  FAIL  %-46s RC=%s want=%s\n' "$label" "$rc" "$want"; sed -n '1,3p' "$W/go" | sed 's/^/          /'; fi
  }
  rm -f "$REC"
  g 2 "24 no recipient file -> UNEVALUATED"      RECIPIENT_FILE="$REC" DEST="$GD" REPO="$REPO"
  printf 'not-a-recipient\n' > "$REC"
  g 2 "25 malformed recipient -> UNEVALUATED"    RECIPIENT_FILE="$REC" DEST="$GD" REPO="$REPO"
  printf 'age1q4mqprrl67lxvwuwu3stq8y5yhe9ke3huzy5usenqjdvvc2r0ufq4a8scp\n' > "$REC"
  g 1 "26 dest unmounted -> refuse"              RECIPIENT_FILE="$REC" DEST="$W/guardmissing" REPO="$REPO"
  if [ -d "$W/guardmissing" ]; then fail=$((fail+1)); echo "      FAIL 27 the guard created the destination itself"
  else pass=$((pass+1)); echo "  ok    27 guard did not create the destination"; fi
  mkdir -p "$GD"; : > "$GD/jol-control-terraform.tfstate.20260101T000000Z.age"
  # The guard now refuses to call a snapshot fresh unless its sidecar names the lineage it protects
  # (cases 46-50). These three cases are about AGE and device refusal, so the fixture supplies a matching
  # sidecar and lets them reach the behaviour they were written to assert. In CI there is no
  # terraform.tfstate, the live lineage reads empty, and the identity rule stays inert by design.
  printf 'lineage   : %s\nmd5  : fixture\n' "$(jq -r '.lineage // "unknown"' "$REPO/terraform.tfstate" 2>/dev/null || echo unknown)" \
    > "$GD/jol-control-terraform.tfstate.20260101T000000Z.age.info"
  g 0 "28 fresh snapshot -> nothing to do"       RECIPIENT_FILE="$REC" DEST="$GD" REPO="$REPO" MAX_AGE_H=24
  if grep -q 'nothing to do' "$W/go"; then pass=$((pass+1)); echo "  ok    29 it names the no-op (silent success is not enough)"
  else fail=$((fail+1)); echo "  FAIL  29 succeeded without saying why"; sed -n '1,2p' "$W/go" | sed 's/^/          /'; fi
  # Stale snapshot: the guard must try, and the inner script's device check must stop it (this
  # destination is a temp dir on the state's own disk), surfacing as a refusal not a pass.
  g 1 "30 stale, dest on the state's disk -> refuse" RECIPIENT_FILE="$REC" DEST="$GD" REPO="$REPO" MAX_AGE_H=0
  if [ "$(find "$GD" -type f | wc -l)" = 2 ]; then pass=$((pass+1)); echo "  ok    31 refused run left no artefact behind (snapshot + its sidecar only)"
  else fail=$((fail+1)); echo "  FAIL  31 artefacts left by a refused run: $(find "$GD" -type f | wc -l) (want 2)"; fi
  # A non-numeric clock must produce UNEVALUATED, not a bash arithmetic crash.
  mkdir -p "$W/baddate"; printf '#!/bin/sh\necho 19700101T000000Z\n' > "$W/baddate/date"; chmod +x "$W/baddate/date"
  brc=0; timeout 120 env PATH="$W/nolog:$W/baddate:/usr/bin:/bin" RECIPIENT_FILE="$REC" DEST="$GD" \
      REPO="$REPO" MAX_AGE_H=24 bash "$GUARD" </dev/null >"$W/go" 2>&1 || brc=$?
  if [ "$brc" = 2 ] && grep -q 'cannot compute snapshot age' "$W/go"; then
    pass=$((pass+1)); printf '  ok    %-46s RC=2, named the cause\n' "32 broken date -> UNEVALUATED"
  else fail=$((fail+1)); printf '  FAIL  %-46s RC=%s\n' "32 broken date -> UNEVALUATED" "$brc"; sed -n '1,2p' "$W/go" | sed 's/^/          /'; fi
  rm -f "$REC"; find "$GD" -type f -delete 2>/dev/null; rmdir "$GD" 2>/dev/null
else
  skip=$((skip+9)); echo "  SKIP   scheduled-refresh guard absent ($GUARD) - 9 cases not evaluated"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 33-45: the off-machine custody rehearsal (scripts/offhost_rehearsal.sh) and the status pull
# (scripts/backup_status.sh). These cases exist because the first version of this instruction was
# handed to a human untested and failed three ways: a manifest of ABSOLUTE paths that "verified" only
# because the source files were still at home, a private identity staged in a world-writable /tmp, and
# a status gate whose success code was unreachable. Each is asserted here, and every mutation test
# first proves the mutation TOOK (age-keygen silently refuses to overwrite, which made one early case
# pass for the wrong reason).
# ─────────────────────────────────────────────────────────────────────────────
RH="$REPO/scripts/offhost_rehearsal.sh"
ST="$REPO/scripts/backup_status.sh"
if [ -f "$RH" ] && [ -f "$ST" ] && command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1; then
  rh(){ # run <expect-rc> <label> <must-say> <VAR=v ...> -- <command...>
    local want=$1 label=$2 says=$3; shift 3
    local envs=(); while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    if [ $# -eq 0 ] || [ "$1" != "--" ]; then fail=$((fail+1)); echo "  FAIL  $label: helper misuse, no -- separator"; return 0; fi
    shift
    local rc=0; timeout 180 env "${envs[@]}" "$@" </dev/null >"$W/rho" 2>&1 || rc=$?
    local verdict=ok
    [ "$rc" = "$want" ] || verdict="RC=$rc want=$want"
    grep -qF -- "$says" "$W/rho" || verdict="$verdict; expected text missing"
    # `|| true` on every counter: this suite runs WITHOUT errexit by design (`set -uo pipefail`), and
    # a `set -e` left over from a neighbouring case used to abort the whole file mid-block, silently
    # dropping every later case. grep -c exits 1 when it counts zero, so an unprotected assignment is
    # fatal the moment anything turns errexit on.
    local nf nfe; nf=$(grep -c '^FAIL:' "$W/rho" || true); nfe=$(grep '^FAIL:' "$W/rho" | grep -cF -- "$says" || true)
    if [ "$nf" -gt 0 ] && [ "$nf" -ne "$nfe" ]; then verdict="$verdict; a DIFFERENT guard stopped it"; fi
    if [ "$verdict" = ok ]; then pass=$((pass+1)); printf '  ok    %-46s RC=%s\n' "$label" "$rc"
    else fail=$((fail+1)); printf '  FAIL  %-46s %s\n' "$label" "$verdict"; sed -n '1,3p' "$W/rho" | sed 's/^/          /'; fi
    return 0
  }
  RK="$W/rh"; KB="$RK/keydir"; DB="$RK/dest"; HB="$RK/jol-control"
  # The sandbox REPO is deliberately named `jol-control`: the rehearsal derives the snapshot pattern
  # from the repository's basename, so naming it `home` made it hunt for `home-terraform.tfstate.*.age`
  # and every later case fell over. That coupling is the point of the pinning, and it is tested here.
  mkdir -p "$KB" "$DB" "$HB"; chmod 700 "$RK" "$KB"
  age-keygen -o "$KB/state-backup-key.txt"     >/dev/null 2>&1
  age-keygen -o "$KB/state-recovery-test.txt"  >/dev/null 2>&1
  RPUB=$(age-keygen -y "$KB/state-recovery-test.txt"); BKEY=$(age-keygen -y "$KB/state-backup-key.txt")
  printf '%s\n' "$RPUB" > "$KB/offdisk-recipient.txt"
  # 88 KB of plausible state: a 187-byte fixture sailed past the size floor and made three later
  # cases pass on the wrong assertion, so the payload is deliberately larger than the threshold.
  python3 -c "import json,sys; sys.stdout.write(json.dumps({'version':4,'terraform_version':'1.15.5','serial':306,'lineage':'test','resources':[{'mode':'managed','type':'github_repository','name':'r%d'%i,'instances':[{'attributes':{'name':'jol-%03d'%i}}]} for i in range(600)]}))" > "$RK/plain.json"
  PMD5=$(md5sum "$RK/plain.json" | cut -d' ' -f1)
  age --encrypt -r "$BKEY" -r "$RPUB" --output "$DB/jol-control-terraform.tfstate.20260101T000000Z.age" "$RK/plain.json"
  printf 'snapshot  : x\nmd5  : %s\nresources   : 600\nrecovery-key-decrypted: yes\nrecovery-key-location : NOT CHECKED\ndevice-check  : verified-different: state=nvme0n1 backup=sdb\n' "$PMD5" > "$DB/jol-control-terraform.tfstate.20260101T000000Z.age.info"
  rm -f "$RK/plain.json"
  RENV=(KEYDIR="$KB" DEST="$DB" REPO="$HB" RECIPIENT_FILE="$KB/offdisk-recipient.txt")

  rh 0 "33 pack builds a packet"                     "CARRY the whole directory" "${RENV[@]}" OUT="$KB/offhost-packet" -- bash "$RH" pack
  dmode=$(stat -c '%a' "$KB/offhost-packet" 2>/dev/null || echo 000)
  if [ "$dmode" = 700 ]; then pass=$((pass+1)); echo "  ok    34 packet dir is 700"
  else fail=$((fail+1)); echo "  FAIL  34 packet dir mode is $dmode, want 700"; fi
  if cut -d' ' -f3- "$KB/offhost-packet/MANIFEST.sha256" | grep -q '/'; then
    fail=$((fail+1)); echo "  FAIL  35 manifest holds PATH SEPARATORS - it cannot verify after relocation"
  else pass=$((pass+1)); echo "  ok    35 manifest is relative (the absolute-path bug is gone)"; fi

  mkdir -p "$RK/world"; chmod 777 "$RK/world"
  rh 1 "36 pack refuses a world-writable parent"     "world-writable" "${RENV[@]}" OUT="$RK/world/packet" -- bash "$RH" pack
  rh 1 "37 pack refuses to stage inside the repo"    "inside the repository" "${RENV[@]}" OUT="$HB/packet" -- bash "$RH" pack
  rh 1 "38 pack refuses to overwrite a packet"       "already exists" "${RENV[@]}" OUT="$KB/offhost-packet" -- bash "$RH" pack

  # Relocate, then DELETE the source. Without the delete the old absolute manifest "verified" the
  # originals and reported success for a copy that was never checked.
  cp -a "$KB/offhost-packet" "$RK/carried"; rm -rf "$KB/offhost-packet"
  rh 0 "39 verify after relocation, source deleted"  "PASS: snapshot" -- bash "$RK/carried/offhost_rehearsal.sh" verify
  grep -q "md5 $PMD5" "$W/rho" || { echo "  note   39 PASS did not quote the fixture md5"; }
  RTOK=$(sed -n 's/^  ATTEST \([0-9a-f]\{32\}\) .*/\1/p' "$RK/vtok" 2>/dev/null)
  timeout 120 bash "$RK/carried/offhost_rehearsal.sh" verify </dev/null >"$RK/vtok" 2>&1 || true
  RTOK=$(sed -n 's/^  ATTEST \([0-9a-f]\{32\}\) .*/\1/p' "$RK/vtok")
  if [ ${#RTOK} = 32 ]; then pass=$((pass+1)); echo "  ok    40 verify emitted a 32-char attestation token"
  else fail=$((fail+1)); echo "  FAIL  40 no token emitted (${#RTOK} chars) - round trip cannot complete"; fi

  rh 1 "41 attest rejects a wrong token"             "does not match the outstanding challenge" "${RENV[@]}" -- bash "$RH" attest 00000000000000000000000000000000
  rh 0 "42 attest accepts the recovered token"       "ATTESTED: recorded" "${RENV[@]}" -- bash "$RH" attest "$RTOK"
  rh 1 "43 the same token cannot be used twice"      "no outstanding challenge" "${RENV[@]}" -- bash "$RH" attest "$RTOK"

  cp -a "$RK/carried" "$RK/tam"; printf 'x' >> "$RK/tam/attest-challenge.age"
  rh 1 "44 tampered packet fails the manifest"       "manifest mismatch" -- bash "$RK/tam/offhost_rehearsal.sh" verify
  if grep -q 'challenge decrypted' "$W/rho"; then fail=$((fail+1)); echo "  FAIL  44 decrypt ran anyway - manifest is not a gate"; fi
  cp -a "$RK/carried" "$RK/wk"; rm -f "$RK/wk/state-recovery-test.txt"
  age-keygen -o "$RK/wk/state-recovery-test.txt" >/dev/null 2>&1
  if [ "$(age-keygen -y "$RK/wk/state-recovery-test.txt")" = "$RPUB" ]; then
    fail=$((fail+1)); echo "  FAIL  45 key swap did not take - that case would pass vacuously"
  else
    rm -f "$RK/wk/MANIFEST.sha256"; ( cd "$RK/wk" && sha256sum -- * > MANIFEST.sha256 )
    rh 1 "45 wrong identity cannot open its challenge" "cannot open its own challenge" -- bash "$RK/wk/offhost_rehearsal.sh" verify
  fi
else
  skip=$((skip+13)); echo "  SKIP   rehearsal scripts or age absent - 13 cases not evaluated"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 46-50: whose snapshot is this? Found live on 2026-10-27: another tree (jolarca-control) started
# writing `terraform.tfstate.s17.*.age` into the SAME destination this guard reads, and the guard's
# `newest *.age` glob let its file satisfy ours - `RC=0 nothing to do` while the jol-control inventory
# was hours stale. Three separate holes were in that one line: no name pinning, no future-mtime rule
# (a 2099 mtime logged "-632713h old (< 24h)" and passed), and no proof the snapshot protects THIS
# state. Needs jq, the guard, and a real terraform.tfstate to read a lineage from, so it SKIPs on a
# runner that has no state - never a silent pass.
# ─────────────────────────────────────────────────────────────────────────────
if [ -f "$GUARD" ] && [ -s "$REPO/terraform.tfstate" ]; then
  LIVE_LIN_TEST=$(jq -r '.lineage // empty' "$REPO/terraform.tfstate" 2>/dev/null || true)
  SD="$W/sep"; mkdir -p "$SD"
  printf 'age1testonlytest\n' > "$SD/rec"
  gsay(){ sed -n 's/.*state-backup-guard\[[0-9]*\]: //p' "$W/gs"; }
  rung(){ local want=$1 label=$2 says=$3 nosay=$4; shift 4
    local rc=0; timeout 180 env REPO="$REPO" RECIPIENT_FILE="$SD/rec" "$@" \
      bash "$GUARD" </dev/null >"$W/gs" 2>&1 || rc=$?
    local v=ok
    [ "$rc" = "$want" ] || v="RC=$rc want=$want"
    if [ -n "$says" ] && ! grep -qF -- "$says" "$W/gs"; then v="$v; missing text"; fi
    if [ -n "$nosay" ] && grep -qF -- "$nosay" "$W/gs"; then v="$v; said the FORBIDDEN thing: $nosay"; fi
    if [ "$v" = ok ]; then pass=$((pass+1)); printf '  ok    %-46s RC=%s\n' "$label" "$rc"
    else fail=$((fail+1)); printf '  FAIL  %-46s %s\n' "$label" "$v"; gsay | sed -n '1,3p' | sed 's/^/          /'; fi
  }
  # 46 a foreign snapshot, newer than anything of ours, must not be treated as our backup
  rm -rf "$SD/d"; mkdir -p "$SD/d"
  : > "$SD/d/terraform.tfstate.s17.29990101T000000Z.age"; touch -d '2099-01-01' "$SD/d/terraform.tfstate.s17.29990101T000000Z.age"
  # expect 1, not 2: with no snapshot of ours the guard correctly tries to make one, and backup_state.sh
  # then refuses this sandbox destination because it sits on the state's own disk. The property under
  # test is "the foreign file did not silence us", which the forbidden `nothing to do` phrase pins.
  rung 1 "46 foreign snapshot cannot satisfy us" "no snapshot present" "nothing to do" \
    DEST="$SD/d" MAX_AGE_H=999999
  # 47 a FUTURE mtime on our own name is a broken clock or a planted file, not freshness
  : > "$SD/d/jol-control-terraform.tfstate.29990101T000000Z.age"
  touch -d '2099-01-01' "$SD/d/jol-control-terraform.tfstate.29990101T000000Z.age"
  rung 2 "47 future mtime -> UNEVALUATED"        "future mtime"                 "nothing to do" \
    DEST="$SD/d" MAX_AGE_H=999999
  # 48 right name, fresh, but protecting a DIFFERENT inventory -> must not read as healthy
  rm -f "$SD/d"/*.age "$SD/d"/*.info
  : > "$SD/d/jol-control-terraform.tfstate.20260101T000000Z.age"
  printf 'lineage   : 00000000-diff-erent-inventory-000000\nmd5  : x
' > "$SD/d/jol-control-terraform.tfstate.20260101T000000Z.age.info"
  rung 1 "48 foreign lineage forces past freshness" "DIFFERENT inventory" "nothing to do" \
    DEST="$SD/d" MAX_AGE_H=999999
  # 49 an unidentified snapshot is UNEVALUATED, never a pass
  rm -f "$SD/d"/*.info; printf 'md5  : x\n' > "$SD/d/jol-control-terraform.tfstate.20260101T000000Z.age.info"
  rung 2 "49 snapshot with no lineage is UNVERIFIED" "no lineage recorded"  "nothing to do" \
    DEST="$SD/d" MAX_AGE_H=999999
  # 50 and the identity case the guard was missing: correct lineage IS accepted as fresh
  rm -f "$SD/d"/*.info
  printf 'lineage   : %s\nmd5  : x\n' "$LIVE_LIN_TEST" > "$SD/d/jol-control-terraform.tfstate.20260101T000000Z.age.info"
  rung 0 "50 our own lineage + fresh = nothing to do" "nothing to do" "DIFFERENT inventory" \
    DEST="$SD/d" MAX_AGE_H=999999
  rm -rf "$SD"
else
  skip=$((skip+5)); echo "  SKIP   guard or a real terraform.tfstate absent - 5 identity cases not evaluated"
fi

echo "---"
echo "backup-gate self-test: $pass passed, $fail failed, $skip skipped"
if [ "$fail" -gt 0 ]; then echo "FAILED — $fail backup-gate violation(s)"; exit 1; fi
if [ "$pass" -lt 24 ]; then
  # 24 is the measured census of cases that run with `age` hidden and no real state: guards 1-9,
  # device cases 21-23, repo/fence/umask 18-20, and the scheduled-refresh block 24-32. Measured from
  # an actual hidden-age run, not guessed - a threshold under the true count turns a broken suite
  # green, and one above it makes every CI run red, which is the S1-012 failure mode again.
  echo "UNEVALUATED — only $pass cases ran; the guard set is incomplete, this is not a pass"; exit 2
fi
if [ "$skip" -gt 0 ] && [ "$pass" -lt 24 ]; then
  echo "UNEVALUATED — $skip cases skipped and only $pass ran; not a pass"; exit 2
fi
echo "PASSED — $pass backup-gate tests, 0 failures$([ "$skip" -gt 0 ] && echo " ($skip crypto cases skipped)")."
exit 0
