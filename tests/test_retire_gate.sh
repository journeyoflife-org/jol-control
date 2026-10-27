#!/usr/bin/env bash
# tests/test_retire_gate.sh — self-tests for scripts/retire_recovery_key.sh (runbooks.md RB-08).
#
# The gate exists because a recovery identity was destroyed on 2026-10-27 with no off-host copy: the
# runbook said "copy it, verify it, then shred" in prose, the shred was offered as one self-contained
# command line, and it ran first. So the property under test here is not "does it delete" - it is
# "can anything delete the identity WITHOUT proof". Every refusal case therefore also asserts the
# identity is still on disk, because a gate that destroys on failure is worse than no gate.
#
# Exit codes: 0 all cases passed / 1 a violation / 2 cannot-check (age unavailable).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO/scripts/retire_recovery_key.sh"
[ -f "$GATE" ] || { echo "UNEVALUATED — $GATE not found"; exit 2; }
if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
  echo "UNEVALUATED — age/age-keygen absent, the retirement gate cannot be exercised"; exit 2;
fi

W="$(mktemp -d)"; chmod 700 "$W"
trap 'find "$W" -type f -delete 2>/dev/null; rm -rf "$W" 2>/dev/null' EXIT
mkdir -p "$W/iddir" "$W/chal"
umask 077

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %-52s %s\n' "$1" "$2"; }
bad() { fail=$((fail+1)); printf '  FAIL  %-52s %s\n' "$1" "$2"; [ -f "$W/last" ] && sed -n '1,3p' "$W/last" | sed 's/^/          /'; }
mint(){ rm -f "$W/iddir/k.txt"; age-keygen -o "$W/iddir/k.txt" </dev/null >/dev/null 2>&1; }
alive(){ [ -f "$W/iddir/k.txt" ]; }

echo "retire_recovery_key.sh self-test"
echo

mint
timeout 60 env "$GATE" "$W/iddir/k.txt" --challenge-dir "$W/chal" </dev/null >"$W/o" 2>&1
rc=$?
if [ "$rc" = 0 ] && [ -s "$W/chal/offhost-challenge.age" ] && [ -s "$W/chal/offhost-challenge.seal" ] && alive; then
  ok "1 phase 1 writes challenge + seal and destroys nothing" "rc=0"
else bad "1 phase 1 writes challenge + seal and destroys nothing" "rc=$rc"; fi
NONCE="$(sed -n 's/^nonce given : //p' "$W/o")"
if [ -n "$NONCE" ]; then ok "2 a nonce is issued to the operator" "len=${#NONCE}"
else bad "2 a nonce is issued to the operator" "empty"; fi

timeout 60 env "$GATE" "$W/iddir/k.txt" --challenge-dir "$W/chal" --retire </dev/null >"$W/last" 2>&1
rc=$?
if [ "$rc" = 1 ] && alive; then ok "3 retire with NO proof refused, identity survives" "rc=1"
else bad "3 retire with NO proof refused, identity survives" "rc=$rc"; fi

timeout 60 env RETIRE_PROOF=not-the-nonce "$GATE" "$W/iddir/k.txt" --challenge-dir "$W/chal" --retire </dev/null >"$W/last" 2>&1
rc=$?
if [ "$rc" = 1 ] && alive; then ok "4 wrong proof refused, identity survives" "rc=1"
else bad "4 wrong proof refused, identity survives" "rc=$rc"; fi

# The seal must not contain the nonce in cleartext, or anyone holding the host passes the test that
# exists to prove they are not the host.
if grep -rqF -- "$NONCE" "$W/chal" "$W/iddir" 2>/dev/null; then
  bad "5 nonce is not recoverable from files on this host" "plaintext nonce found on disk"
else
  ok "5 nonce is not recoverable from files on this host" "seal is a hash"
fi

# The challenge must be openable ONLY by the private half - that is what makes a returned nonce
# evidence of custody rather than of reading a file.
RECV="$(age --decrypt -i "$W/iddir/k.txt" "$W/chal/offhost-challenge.age" </dev/null 2>/dev/null | tr -d '\n')"
if [ -n "$RECV" ] && [ "$RECV" = "$NONCE" ]; then
  ok "6 only the private half recovers the nonce" "round-trip matches"
else
  bad "6 only the private half recovers the nonce" "got '${RECV:0:8}' want '${NONCE:0:8}'"
fi

timeout 60 env RETIRE_PROOF="$NONCE" "$GATE" "$W/iddir/k.txt" --challenge-dir "$W/chal" --retire </dev/null >"$W/last" 2>&1
rc=$?
if [ "$rc" = 0 ] && ! alive && [ ! -e "$W/chal/offhost-challenge.age" ] && [ ! -e "$W/chal/offhost-challenge.seal" ]; then
  ok "7 valid proof retires identity, seal and challenge together" "rc=0, all gone"
else bad "7 valid proof retires identity, seal and challenge together" "rc=$rc"; fi

# Replay: an old nonce must not retire a newly minted identity.
mint
timeout 60 env "$GATE" "$W/iddir/k.txt" --challenge-dir "$W/chal" </dev/null >/dev/null 2>&1
timeout 60 env RETIRE_PROOF="$NONCE" "$GATE" "$W/iddir/k.txt" --challenge-dir "$W/chal" --retire </dev/null >"$W/last" 2>&1
rc=$?
if [ "$rc" = 1 ] && alive; then ok "8 a stale nonce cannot retire a new identity" "rc=1, survives"
else bad "8 a stale nonce cannot retire a new identity" "rc=$rc"; fi

# The challenge must not be written next to the identity: that would let a local file do the work of
# an off-host copy.
timeout 60 env "$GATE" "$W/iddir/k.txt" --challenge-dir "$W/iddir" </dev/null >"$W/last" 2>&1
rc=$?
if [ "$rc" = 1 ] && alive; then ok "9 refuses to place the challenge beside the identity" "rc=1"
else bad "9 refuses to place the challenge beside the identity" "rc=$rc"; fi

# Unreadable identity is UNEVALUATED (2), never a pass and never a silent refusal.
printf 'not an age identity\n' > "$W/iddir/bad.txt"
timeout 60 env "$GATE" "$W/iddir/bad.txt" --challenge-dir "$W/chal" </dev/null >"$W/last" 2>&1
rc=$?
if [ "$rc" = 2 ]; then ok "10 unreadable identity reports UNEVALUATED" "rc=2"
else bad "10 unreadable identity reports UNEVALUATED" "rc=$rc"; fi

# Missing identity file must be a refusal, not a crash.
timeout 60 env "$GATE" "$W/iddir/absent.txt" --challenge-dir "$W/chal" </dev/null >"$W/last" 2>&1
rc=$?
if [ "$rc" = 1 ]; then ok "11 absent identity refused with a reason" "rc=1"
else bad "11 absent identity refused with a reason" "rc=$rc"; fi

# Nothing may be left inside the repository by this suite.
if git -C "$REPO" status --porcelain -uall 2>/dev/null | grep -qiE 'challenge|\.age$'; then
  bad "12 no challenge or key material in the working tree" "found"
else
  ok "12 no challenge or key material in the working tree" ""
fi

echo "---"
echo "retire-gate self-test: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then echo "FAILED — $fail retire-gate violation(s)"; exit 1; fi
echo "PASSED — $pass retire-gate tests, 0 failures."
exit 0
