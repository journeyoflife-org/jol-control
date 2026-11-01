#!/usr/bin/env bash
# RB-08: retire an age recovery identity ONLY after proving somebody else can open it.
#
# Why this exists. On 2026-10-27 an agent-written runbook told the operator to copy a freshly minted
# recovery identity off-host, verify it there, and only then `shred -u` the local file. The shred was
# offered as one self-contained command line and it ran first. The private half was unrecoverable:
# it existed nowhere else on the host (five other age identities and two session transcripts were
# tested for the ability to open the backup; all failed) and the snapshot it protected became
# single-custody. Prose that says "verify first" is advice; advice is not a control.
#
# This makes the proof a precondition instead. The nonce can only be produced by decrypting a file
# that is encrypted to the recipient in question - so presenting it demonstrates that a working copy
# of the identity exists somewhere this machine cannot reach.
#
# Exit codes follow the repository's gate convention:
#   0  proof accepted, identity retired
#   1  refused - proof absent or wrong, the identity is LEFT IN PLACE
#   2  cannot check - the challenge could not be created, so no claim about custody is possible
set -euo pipefail
umask 077          # challenge material and identities are secret-adjacent; default umask here is 002

ID="${1:?usage: scripts/retire_recovery_key.sh <identity-file> [--challenge-dir DIR] [--retire]}"
[ -f "$ID" ] || { echo "FAIL: identity not found: $ID"; exit 1; }
shift
CDIR="."
RETIRE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --challenge-dir) CDIR="${2:?--challenge-dir needs a path}"; shift 2 ;;
    --retire)        RETIRE=1; shift ;;
    *) echo "FAIL: unknown argument '$1'"; exit 1 ;;
  esac
done
if [ ! -d "$CDIR" ] || [ ! -w "$CDIR" ]; then
  echo "FAIL: challenge dir absent or not writable: $CDIR"; exit 1; fi
case "$(cd "$CDIR" && pwd -P)" in
  "$(cd "$(dirname "$ID")" && pwd -P)")
    echo "FAIL: the challenge must be written somewhere OTHER than the identity's own directory,";
    echo "      so that proving custody means carrying a file off it, not reading a neighbour."; exit 1;;
esac

# Proving custody of a COPY requires somewhere else to put the proof. The first version of this gate
# checked only that the nonce could be recovered, and the local identity was still present while that
# check ran - so the ceremony could have been satisfied from the same disk, the local copy shredded,
# and the key destroyed with no second copy anywhere. S2-013 recurring with the gate's approval.
# For an irreversible operation, an unprovable separation is a REFUSAL, not a warning.
disk_of(){ local s; s="$(findmnt -no SOURCE --target "$1" 2>/dev/null || true)"; [ -n "$s" ] || { echo ""; return; }
           lsblk -no PKNAME "$s" 2>/dev/null | head -1; }
ID_DISK="$(disk_of "$(dirname "$ID")")"; CH_DISK="$(disk_of "$CDIR")"
if [ -z "$ID_DISK" ] || [ -z "$CH_DISK" ]; then
  echo "FAIL: cannot resolve the physical disk for the identity ('$ID_DISK') or the challenge dir";
  echo "      ('$CH_DISK'). Destroying a private key on an unverifiable separation is not offered;";
  echo "      point --challenge-dir at a directory on the second device (see runbooks.md RB-09)."; exit 1
fi
if [ "$ID_DISK" = "$CH_DISK" ]; then
  echo "FAIL: the challenge dir is on the SAME disk as the identity ($ID_DISK).";
  echo "      A nonce recovered from the disk you are about to wipe proves nothing about a second";
  echo "      copy. Put the challenge on another device first - that is the whole test."; exit 1
fi
echo "separation   : identity on $ID_DISK, challenge on $CH_DISK"

PUB="$(age-keygen -y "$ID" 2>/dev/null)" || { echo "FAIL: $ID is not a readable age identity"; exit 2; }
case "$PUB" in age1*) : ;; *) echo "FAIL: unexpected recipient form '$PUB'"; exit 2 ;; esac

CH="$CDIR/offhost-challenge.age"
SEAL="$CDIR/offhost-challenge.seal"

if [ "$RETIRE" != 1 ]; then
  # Phase 1: mint a nonce only the holder of the private half can recover.
  NONCE="${NONCE:-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
  printf '%s\n' "$NONCE" | age --encrypt --recipient "$PUB" --output "$CH" || {
    echo "FAIL: could not create the challenge ciphertext"; exit 2; }
  # The seal holds the expected answer, hashed. Never in plaintext: this file sits next to the
  # identity, so a plaintext nonce would let anyone with the host pass a test meant to prove
  # they do NOT have the host.
  printf '%s' "$NONCE" | sha256sum | cut -d' ' -f1 > "$SEAL"
  echo "recipient   : $PUB"
  echo "challenge   : $CH"
  # The nonce value is NEVER printed here. Lines 79/84/87 of the previous revision printed it three
  # times, once inside a ready-to-run command line that also lands in shell history and in this
  # terminal's scrollback - so the "proof that a copy exists elsewhere" was obtainable from the very
  # machine the proof is supposed to exclude. For an irreversible action that is worse than the
  # equivalent bug in offhost_rehearsal.sh (finding S2-019), because the failure is not a weak record,
  # it is a destroyed key that nothing can open the backups with.
  echo "nonce       : fingerprint $(printf '%s' "$NONCE" | sha256sum | cut -d' ' -f1 | cut -c1-16)… (value not printed)"
  echo
  echo "NEXT, AND THIS IS THE WHOLE POINT - on the machine that holds the OTHER COPY:"
  echo "  1. copy $CH there (and nothing else; the identity itself must not come back)"
  echo "  2. age --decrypt -i <path to the off-host copy> $(basename "$CH")     # run from inside that dir"
  echo "  3. it prints the nonce; check its fingerprint above, then bring ONLY the value back"
  echo
  echo "Then come back and run, on this host, with NO argument to edit — it prompts and hides the typing:"
  echo "  scripts/retire_recovery_key.sh $ID --challenge-dir $CDIR --retire"
  echo "  (or: make retire-key KEY=$ID CHALLENGE_DIR=$CDIR --retire)"
  echo
  echo "Nothing has been destroyed. The identity stays until the proof is produced."
  exit 0
fi

# Phase 2: only a genuine off-host holder could have produced PROOF.
[ -s "$SEAL" ] || { echo "FAIL: no seal at $SEAL - run phase 1 first (or the seal was lost)."; exit 2; }
[ -s "$CH" ]    || { echo "FAIL: no challenge at $CH - run phase 1 first."; exit 2; }
if [ -z "${RETIRE_PROOF:-}" ]; then
  # Prompt rather than demand an argument. A placeholder an operator must substitute has broken five
  # instructions in this project, one of them this exact line (`PROOF=<that-nonce>` typed literally,
  # `bash: syntax error near unexpected token 'newline'`).
  printf 'proof nonce from the off-host copy (32 hex, input hidden): ' >&2
  # No terminal to read from is a REFUSAL (1), not UNEVALUATED (2): nothing is unknown, the proof simply
  # was not offered, and the identity must stay. Exit 2 here would blur "cannot ask" into "cannot tell".
  IFS= read -r -s RETIRE_PROOF || { echo "REFUSED: no proof offered and no terminal to ask for it."
    echo "         Run this interactively, or pass RETIRE_PROOF=<the 32 hex from the other machine>." >&2
    exit 1; }
  printf '\n' >&2
fi
RETIRE_PROOF="$(printf '%s' "$RETIRE_PROOF" | tr -d ' \t\r\n')"
# shellcheck disable=SC2016  # literal placeholder shapes are what is being detected, not expanded
case "$RETIRE_PROOF" in
  *'<'*|*'…'*|*'$('*|'the')
    echo "REFUSED: that is placeholder text from the instructions, not a nonce. Run the --retire command"
    echo "         with no RETIRE_PROOF and paste the 32 hex digits at the prompt."; exit 1 ;;
esac
printf '%s' "$RETIRE_PROOF" | grep -qE '^[0-9a-f]{32}$' || {
  echo "REFUSED: proof must be 32 hex digits; got ${#RETIRE_PROOF} characters (value not echoed)."
  echo "         The identity is left exactly where it was."; exit 1; }
EXPECTED="$(cat "$SEAL")"
ACTUAL="$(printf '%s' "$RETIRE_PROOF" | sha256sum | cut -d' ' -f1)"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "REFUSED: the proof does not match the challenge."
  echo "         Expected the nonce that the off-host copy decrypts to; identity left in place at $ID."; exit 1
fi

# Prove the recipient in the challenge really is this identity's, so a matching nonce cannot be
# replayed from an unrelated challenge file.
age --decrypt -i "$ID" "$CH" </dev/null >/dev/null 2>&1 || {
  echo "REFUSED: this identity cannot open its own challenge - the files do not belong together."
  echo "         Nothing destroyed."; exit 1; }

echo "proof accepted: an off-host copy of $PUB recovered the nonce"
shred -u "$ID" 2>/dev/null || rm -f "$ID"
shred -u "$SEAL" 2>/dev/null || rm -f "$SEAL"
shred -u "$CH"   2>/dev/null || rm -f "$CH"
for f in "$ID" "$SEAL" "$CH"; do
  [ -e "$f" ] && { echo "FAIL: $f still exists - retirement incomplete, do NOT treat this path as gone"; exit 1; }
done
echo "retired: identity, seal and challenge removed"
echo "remaining age identities in $(dirname "$ID"):"
find "$(dirname "$ID")" -maxdepth 1 -type f 2>/dev/null | sed 's/^/  /'
echo "OK: custody proven before destruction"
