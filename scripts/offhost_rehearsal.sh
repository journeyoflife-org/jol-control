#!/usr/bin/env bash
# RB-09 step 5: prove the state backup is readable from a key that is NOT on this machine.
#
# Two subcommands, one file. `pack` runs here and writes a self-contained directory; `verify` runs on
# the OTHER machine, from inside that directory, and needs no paths editing - it locates itself. The
# token then carried back is what makes the difference from an assertion:
#
#   the challenge is encrypted to the recipient, so only a holder of the private half can read the
#   token. Attestation is therefore evidence, not a checkbox someone ticked.
#
# Why not "copy the snapshot and the key and eyeball it": that is what an earlier version of this
# runbook said to do. It left a private identity in /tmp (30-day reap) beside the ciphertext it
# unlocks, named a hard-coded snapshot the daily guard had already superseded, and shipped a manifest
# of absolute paths that "verified" happily - because it was checking the source files still at home,
# not the copies. All three are fixed here and each is covered by a case in tests/test_backup_gate.sh.
#
# Exit codes: 0 verified / 1 refused or mismatch / 2 cannot check.
set -uo pipefail
umask 077

REPO="${REPO:-/opt/jol/repos/jol-control}"
STATE="${STATE:-$REPO/terraform.tfstate}"
DEST="${DEST:-/mnt/jol-backup/jol-control}"
KEYDIR="${KEYDIR:-$HOME/.config/age}"
RECIPIENT_FILE="${RECIPIENT_FILE:-$KEYDIR/offdisk-recipient.txt}"
PENDING_MAX_H="${PENDING_MAX_H:-168}"   # how long a challenge may stay unanswered and still mean something
PENDING="$KEYDIR/offhost-attestation.pending"
ATTESTED="$KEYDIR/offhost-attested"

die() { echo "FAIL: $*"; exit 1; }
unk() { echo "UNEVALUATED: $*"; exit 2; }

need_tools() { if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then unk "age not installed"; fi; }

cmd="${1:-}"; shift || true
case "$cmd" in
## --------------------------------------------------------------------------- pack
pack)
  need_tools
  [ -r "$RECIPIENT_FILE" ] || die "no $RECIPIENT_FILE - record the recipient first (RB-09 step 3)"
  RECIPIENT="$(sed -n '1p' "$RECIPIENT_FILE" | tr -d ' \t')"
  case "$RECIPIENT" in age1*) : ;; *) die "$RECIPIENT_FILE does not hold an age1... recipient" ;; esac
  # Pinned to this repository's snapshot name. On a destination shared with another tree (as this host's
  # now is), `*.age` would happily pack the other project's state and call the rehearsal a success.
  SNAP_GLOB="$(basename "$REPO")-terraform.tfstate.*.age"
  SNAP="$(find "$DEST" -maxdepth 1 -type f -name "$SNAP_GLOB" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
  if [ -z "$SNAP" ] || [ ! -s "$SNAP" ]; then die "no snapshot matching $SNAP_GLOB in $DEST - is the off-device volume mounted? (findmnt -T $DEST)"; fi
  [ -s "$SNAP.info" ] || die "snapshot has no .info sidecar; cannot compare an expected md5"
  IDENTITY="${IDENTITY:-$(find "$KEYDIR" -maxdepth 1 -type f -name 'state-recovery-*' | head -1)}"
  if [ -z "$IDENTITY" ] || [ ! -s "$IDENTITY" ]; then die "no recovery identity found under $KEYDIR; set IDENTITY=<file>"; fi
  # The identity being present here is expected: this machine holds one copy and we are sending a
  # second one elsewhere. Refuse if the caller points at the host key itself - that proves nothing.
  [ "$(sha256sum "$IDENTITY" | cut -d' ' -f1)" != "$(sha256sum "$KEYDIR/state-backup-key.txt" 2>/dev/null | cut -d' ' -f1)" ] \
    || die "IDENTITY is the host key; a second copy of the same key proves no separation"

  OUT="${OUT:-$KEYDIR/offhost-packet}"
  case "$OUT" in
    "$REPO"|"$REPO"/*) die "packet must not be staged inside the repository" ;;
  esac
  # The hazard is not the path SHAPE - an earlier version refused anything under /tmp, which also
  # refused a perfectly good key directory that happened to live there, and passed a world-writable
  # directory somewhere else. Measure it: refuse to stage key material where other accounts can write.
  PARENT="$(dirname "$OUT")"
  mkdir -p "$PARENT" 2>/dev/null
  pmode="$(stat -c '%a' "$PARENT" 2>/dev/null || echo '')"
  if [ -z "$pmode" ]; then die "cannot stat $PARENT - refusing to stage keys blind"; fi
  if [ $(( 8#$pmode & 8#002 )) -ne 0 ]; then
    die "$PARENT is world-writable (mode $pmode); a key placed there is readable-in-principle to other accounts - stage under a 700 directory"
  fi
  if [ -e "$OUT" ]; then die "$OUT already exists - remove it deliberately, do not overwrite a packet in flight"; fi
  mkdir -p "$OUT" || die "cannot create $OUT"

  if [ -s "$PENDING" ]; then
    # An outstanding challenge is about to be replaced, which makes any packet already in transit
    # permanently unattestable: its hash is gone, so a legitimate off-host holder would be refused and
    # the operator would conclude the copy is broken. This happened while writing these lines - the
    # packet was re-packed to carry a fixed script. Warn, never block: abandoning a lost packet must not
    # become impossible.
    echo "WARN: replacing an outstanding challenge issued $(sed -n 's/^issued=//p' "$PENDING") -"
    echo "      any packet already away from this machine can no longer be attested. If one is"
    echo "      in transit, finish it (verify + attest) before trusting this new packet."
  fi
  # Split delivery by default. A packet carrying the identity AND the ciphertext it opens means one
  # lost stick, one intercepted email, one laptop surrendered for repair yields the key and the data in
  # one act - the exact single-carrier failure S2-014 was about, reproduced in the remedy for it. So the
  # key is expected to already be on the far machine (placed once, by hand: password manager, printed,
  # an encrypted volume) or to travel separately. WITH_KEY=1 puts it back in, for the first placement.
  WITH_KEY="${WITH_KEY:-0}"
  if [ "$WITH_KEY" = 1 ]; then
    echo "WITH_KEY=1: the private identity is being carried INSIDE the packet. Use this only to place the"
    echo "            first copy, and treat that packet as secret material end to end."
  fi
  TOKEN="${TOKEN:-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
  [ "${#TOKEN}" -ge 16 ] || die "token is too short to be a challenge nonce"
  printf '%s\n' "$TOKEN" | age --encrypt --recipient "$RECIPIENT" --output "$OUT/attest-challenge.age" || die "could not write the challenge"
  if [ "$WITH_KEY" = 1 ]; then
    cp -p "$SNAP" "$SNAP.info" "$IDENTITY" "$OUT/" || die "copy failed"
  else
    cp -p "$SNAP" "$SNAP.info" "$OUT/" || die "copy failed"
  fi
  cp -p "$0" "$OUT/offhost_rehearsal.sh" 2>/dev/null || die "could not copy this script into the packet"
  chmod 600 "$OUT"/* 2>/dev/null
  # No angle brackets anywhere in what follows, and the text also lands in HOWTO.txt inside the packet.
  # A placeholder an operator must edit before running is a defect with a known failure mode: this is the
  # fifth such instance in one day. `verify` locates its own directory, so the only thing the far side has
  # to choose is where to put the folder - which needs no command line at all.
  HOWTO="Carry this whole directory to the other machine by any means that is not this machine. Put it
wherever you like, then cd into that directory and run the next two lines from inside it:

    sha256sum -c MANIFEST.sha256
    bash offhost_rehearsal.sh verify

WHAT IS IN THIS PACKET: one age-encrypted snapshot, its sidecar, a challenge ciphertext, and this
script. The private identity is NOT in here by default - split delivery. The other machine must already
hold the key copy (placed once by hand: password manager entry, printed sheet in a fireproof box, an
encrypted volume). If it does not, re-run 'make backup-pack WITH_KEY=1' for that first placement and
treat the resulting packet as secret material end to end.

TRANSPORT. The .age files are safe over any channel - age ciphertext carries no plaintext and no
material capable of decrypting it. The key is the opposite: never transmit it by email, chat, cloud
drive, or a pastebin. A loss of the packet alone yields ciphertext nobody can open; that asymmetry is
the entire reason for split delivery.

verify checks the manifest BEFORE decrypting anything, then prints a 32-hex token. Bring only that
number back and run, on this machine:

    make backup-attest

It prompts and hides what you type. Then delete this directory from the other machine, unless that
machine is where custody is meant to live:

    find \"\$PWD\" -maxdepth 1 -type f -exec shred -u {} + && rmdir \"\$PWD\"

Do NOT run verify on this machine: it prints the token here, and a token that reached this terminal is
no longer evidence that a key exists elsewhere."
  printf '%s\n' "$HOWTO" > "$OUT/HOWTO.txt"; chmod 600 "$OUT/HOWTO.txt"
  ( cd "$OUT" && sha256sum -- * > MANIFEST.sha256 ) || die "manifest generation failed"
  printf 'issued=%s\nrecipient=%s\nsnapshot=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RECIPIENT" "$(basename "$SNAP")" > "$PENDING"
  printf 'tokenhash=%s\n' "$(printf '%s' "$TOKEN" | sha256sum | cut -d' ' -f1)" >> "$PENDING"
  chmod 600 "$PENDING"

  echo "packet    : $OUT  (mode 700, contents 600)"
  echo "snapshot  : $(basename "$SNAP")"
  echo "identity  : $(basename "$IDENTITY")  $( [ "$WITH_KEY" = 1 ] && echo '(INSIDE the packet)' || echo '(NOT in the packet - the far machine must already hold it)' )"
  echo "recipient : $RECIPIENT"
  echo "howto     : $OUT/HOWTO.txt  (travels with the packet; every step below is also in it)"
  echo
  echo "CARRY the whole directory. On the other machine, cd INTO it and run those two lines from there:"
  echo "  sha256sum -c MANIFEST.sha256"
  echo "  bash offhost_rehearsal.sh verify"
  echo
  echo "Attest on THIS machine with no argument - it will ask for the token and hide what you type:"
  echo "  make backup-attest"
  # The token value is deliberately NOT printed here. It is the secret half of a proof-of-possession:
  # printing it into stdout puts it in terminal scrollback, agent transcripts and any captured log, and
  # anyone holding the transcript could then attest without holding any key - which is precisely the
  # difference between evidence and a checkbox. Only the hash fingerprint appears, and only the private
  # half can recover the value itself.
  echo "challenge  : token-sha256 $(printf '%s' "$TOKEN" | sha256sum | cut -c1-16)… (value never printed; it must be recovered by decrypting)"
  ;;
## --------------------------------------------------------------------------- verify
verify)
  need_tools
  # Am I the source host? The pending/attested records live only on the machine that issued the
  # challenge, and that machine also holds a copy of the identity - so running verify here would find a
  # key, decrypt everything, print a token, and call it proof. It would be a restore rehearsal wearing a
  # custody proof's clothes. Refuse unless told explicitly that a local rehearsal is what is wanted, and
  # even then withhold the token, because a token produced on the source host must not be attestable.
  SOURCE_HOST=0
  if [ -s "$PENDING" ] || [ -s "$ATTESTED" ]; then SOURCE_HOST=1; fi
  if [ "$SOURCE_HOST" = 1 ] && [ "${LOCAL_OK:-0}" != 1 ]; then
    die "this looks like the SOURCE host (an outstanding or consumed challenge record is here) and the identity is on this machine, so decrypting here proves nothing about a copy elsewhere. Finish the rehearsal on the other machine. To rehearse the RESTORE locally instead, re-run with LOCAL_OK=1 - it will not print a token and cannot be attested."
  fi
  if [ "$SOURCE_HOST" = 1 ]; then
    echo "WARNING: local restore rehearsal on the source host. This is NOT off-host custody evidence"
    echo "         and no attestation token will be printed."
  fi
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$HERE" || die "cannot enter $HERE"
  [ -s MANIFEST.sha256 ] || die "no MANIFEST.sha256 beside me - this is not a packet directory"
  if ! sha256sum -c MANIFEST.sha256; then
    die "manifest mismatch: the packet was altered or truncated in transit; do not attest"
  fi
  IDENTITY="$(find . -maxdepth 1 -type f -name '*recovery*.txt' | head -1)"
  if [ -z "$IDENTITY" ]; then
    # No key in the packet (the default, split delivery). Look for the placed copy in the standard local
    # locations - but NEVER fall back to age's ambient identity resolution (an agent, or
    # ~/.config/age/identities), because a key that merely happens to live on the receiving machine would
    # then satisfy a proof that is supposed to show a SEPARATE custodied copy exists.
    # Unquoted on purpose: PLACED_SEARCH is a space-separated list of directories, not one path.
    # shellcheck disable=SC2086
    found="$(find ${PLACED_SEARCH:-"$HOME/.config/age /mnt/jol-backup"} -maxdepth 3 -type f -name 'state-recovery-*' 2>/dev/null | head -1)"
    if [ -n "$found" ] && [ "$(sha256sum "$found" | cut -d' ' -f1)" \
         != "$(sha256sum "$HOME/.config/age/state-backup-key.txt" 2>/dev/null | cut -d' ' -f1)" ]; then
      IDENTITY="$found"
      echo "note: no identity in the packet; using the locally placed copy at $found"
      echo "      That is a valid proof of a second copy IF this machine is not the source host."
    fi
  fi
  [ -n "$IDENTITY" ] || die "no recovery identity in the packet and none placed on this machine. Put the key copy here first (separately from the packet), or re-pack with WITH_KEY=1 for the initial placement."
  [ -s "$IDENTITY" ] || die "the identity at $IDENTITY is empty or unreadable"
  SNAP="$(find . -maxdepth 1 -type f -name 'jol-control-terraform.tfstate.*.age' | head -1)"
  if [ -z "$SNAP" ] || [ ! -s "$SNAP.info" ]; then die "no snapshot + sidecar pair inside the packet"; fi
  CHALLENGE=./attest-challenge.age
  [ -s "$CHALLENGE" ] || die "no attest-challenge.age in the packet"

  PLAIN="$(mktemp)"
  cleanup(){ rm -f "$PLAIN" "$PLAIN.err" 2>/dev/null; }
  trap cleanup EXIT

  age --decrypt -i "$IDENTITY" "$CHALLENGE" > "$PLAIN" 2>/dev/null
  crc=$?
  [ "$crc" -eq 0 ] || die "the identity in this packet cannot open its own challenge (age exit $crc)"
  TOKEN="$(tr -d '\n' < "$PLAIN")"
  [ "${#TOKEN}" -ge 16 ] || die "challenge decrypted to something too short to be a token"

  # The restore half: prove the snapshot this packet carries is readable AND matches what the source
  # recorded, not merely that some key works.
  want="$(sed -n 's/^md5  *: //p' "$SNAP.info")"
  age --decrypt -i "$IDENTITY" "$SNAP" > "$PLAIN" 2>/dev/null
  drc=$?; sz="$(stat -c%s "$PLAIN" 2>/dev/null || echo 0)"
  got="$(md5sum "$PLAIN" 2>/dev/null | cut -d' ' -f1)"
  [ "$drc" -eq 0 ] || die "snapshot decrypt failed (age exit $drc)"
  [ "$sz" -gt 1000 ] || die "snapshot decrypted to $sz bytes - nothing usable came out"
  [ "$got" != d41d8cd98f00b204e9800998ecf8427e ] || die "md5 of empty input; the decrypt produced nothing"
  [ "$got" = "$want" ] || die "md5 $got does not match the sidecar's $want - DIFFERENT INVENTORY"

  echo "PASS: snapshot $(basename "$SNAP") decrypts to md5 $got ($sz bytes), matching the sidecar"
  echo "      challenge decrypted with $(basename "$IDENTITY") (from $(dirname "$IDENTITY")); the same key opens both"
  if [ "$SOURCE_HOST" = 1 ]; then
    echo
    echo "NOT AN ATTESTATION: this ran on the source host, so the token is withheld. The restore half is"
    echo "proven (the snapshot opens and matches its sidecar); custody is not."
    exit 0
  fi
  echo
  echo "ATTEST with the token on the line below. Run 'make backup-attest' on the source machine and paste"
  echo "it at the prompt (32 hex, input hidden). Nothing else from this machine needs to come back:"
  echo "  $TOKEN"
  echo "(printing it HERE is deliberate: on this machine the value is only obtainable by someone already"
  echo " holding the identity, which is the whole point - do NOT run 'verify' back on the source host,"
  echo " because that puts the answer into this machine's scrollback and transcripts and voids the proof)"
  echo
  echo "Then DELETE this packet directory from the machine you copied it to, unless that machine is"
  echo "where you intend the custody copy to live:"
  echo "  find \"\$PWD\" -maxdepth 1 -type f -exec shred -u {} + && rmdir \"\$PWD\""
  ;;
## --------------------------------------------------------------------------- attest (source machine)
attest)
  # The token arrives by PROMPT, not by a placeholder in a command line. Four commands handed to a human
  # in this project have been broken by an angle-bracket stand-in typed literally into a shell
  # (`PROOF=<that-nonce>`, `CHALLENGE_DIR=/tmp`, a `backup.sh` that never existed, and
  # `make backup-attest TOKEN=<the 32 hex it prints>` which produced `bash: syntax error near
  # unexpected token 'newline'`). An instruction that must be edited before it can run is the defect;
  # running it with no argument and pasting at the prompt is the same action with nothing to get wrong.
  TOKEN="${1:-}"
  if [ -z "$TOKEN" ]; then
    printf 'challenge token from the ATTEST line (32 hex, input hidden): ' >&2
    IFS= read -r -s TOKEN || unk "no token supplied (read failed)"
    printf '\n' >&2
  fi
  TOKEN="$(printf '%s' "$TOKEN" | tr -d ' \t\r\n')"
  # Single quotes are deliberate: these are literal placeholder shapes, not expansions.
  # shellcheck disable=SC2016
  case "$TOKEN" in
    *'<'*|*'…'*|*'$('*|'the')
      die "that is the placeholder text from the instructions, not a token. Run 'make backup-attest' with no argument and paste the 32 hex digits the other machine printed."
      ;;
  esac
  printf '%s' "$TOKEN" | grep -qE '^[0-9a-f]{32}$' \
    || die "token must be 32 hex digits; got ${#TOKEN} characters (the value is not echoed here)"
  [ -s "$PENDING" ] || die "no outstanding challenge in $PENDING - run 'pack' first"
  issued="$(sed -n 's/^issued=//p' "$PENDING")"
  # A challenge with no lifetime stays satisfiable forever. What gets recorded is "a copy exists elsewhere
  # and works"; a nonce recovered eleven months later, from a drive since reformatted or lost, would still
  # write a fresh attested= timestamp and hush the gate for another 30 days. Bound the unanswered window
  # the same way the attestation itself expires.
  PENDING_MAX_H="${PENDING_MAX_H:-168}"
  its="$(date -u -d "$issued" +%s 2>/dev/null || echo 0)"
  if [ "$its" -le 0 ]; then
    die "cannot read the issue time in $PENDING ('$issued') - refusing to attest against an undated challenge"
  fi
  age_h=$(( ( $(date -u +%s) - its ) / 3600 ))
  if [ "$age_h" -gt "$PENDING_MAX_H" ]; then
    die "challenge was issued ${age_h}h ago (> ${PENDING_MAX_H}h) - a token recovered that late proves nothing current; run 'make backup-pack' again"
  fi
  want="$(sed -n 's/^tokenhash=//p' "$PENDING")"
  rec="$(sed -n 's/^recipient=//p' "$PENDING")"
  snap="$(sed -n 's/^snapshot=//p' "$PENDING")"
  issued="$(sed -n 's/^issued=//p' "$PENDING")"
  [ -n "$want" ] || die "outstanding record has no tokenhash - refusing to attest"
  got="$(printf '%s' "$TOKEN" | sha256sum | cut -d' ' -f1)"
  [ "$got" = "$want" ] || die "token does not match the outstanding challenge - not attested"
  { printf 'attested=%s\nrecipient=%s\nsnapshot=%s\nchallenge-issued=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rec" "$snap" "$issued"
    printf 'proof=a nonce encrypted to the recipient was recovered by decrypting on another machine;\n'
    printf '     the token was never printed on this host, and the source host refuses to run verify\n'
  } > "$ATTESTED"
  chmod 600 "$ATTESTED"
  rm -f "$PENDING"
  echo "ATTESTED: recorded in $ATTESTED"
  echo "Note plainly: this proves a copy of the key that decrypts the challenge exists somewhere other"
  echo "than this machine. It does not prove that machine is offsite, fireproof, or that the snapshot"
  echo "it holds is current - those remain RB-09 step 5's monthly rehearsal."
  ;;
*)
  echo "usage: scripts/offhost_rehearsal.sh pack | verify | attest <token>"
  exit 2
  ;;
esac
