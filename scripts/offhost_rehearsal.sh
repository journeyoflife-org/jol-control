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
DEST="${DEST:-/mnt/jol-backup/jol-state-backup}"
KEYDIR="${KEYDIR:-$HOME/.config/age}"
RECIPIENT_FILE="${RECIPIENT_FILE:-$KEYDIR/offdisk-recipient.txt}"
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

  TOKEN="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  printf '%s\n' "$TOKEN" | age --encrypt --recipient "$RECIPIENT" --output "$OUT/attest-challenge.age" || die "could not write the challenge"
  cp -p "$SNAP" "$SNAP.info" "$IDENTITY" "$OUT/" || die "copy failed"
  cp -p "$0" "$OUT/offhost_rehearsal.sh" 2>/dev/null || die "could not copy this script into the packet"
  chmod 600 "$OUT"/* 2>/dev/null
  # RELATIVE names, generated from inside the directory, so the manifest travels with the packet.
  ( cd "$OUT" && sha256sum -- * > MANIFEST.sha256 ) || die "manifest generation failed"
  printf 'issued=%s\nrecipient=%s\nsnapshot=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RECIPIENT" "$(basename "$SNAP")" > "$PENDING"
  printf 'tokenhash=%s\n' "$(printf '%s' "$TOKEN" | sha256sum | cut -d' ' -f1)" >> "$PENDING"
  chmod 600 "$PENDING"

  echo "packet    : $OUT  (mode 700, contents 600)"
  echo "snapshot  : $(basename "$SNAP")"
  echo "identity  : $(basename "$IDENTITY")"
  echo "recipient : $RECIPIENT"
  echo
  echo "CARRY the whole directory to the other machine (nothing else back), then run THERE:"
  echo "  cd <where you put it> && sha256sum -c MANIFEST.sha256 && bash offhost_rehearsal.sh verify"
  echo
  echo "It prints an ATTEST line. Bring only that line back and run:"
  echo "  make backup-attest TOKEN=<the token it prints>"
  echo "Here is the local token, for comparison only - it must be obtained by decrypting, not by reading this line:"
  echo "  $TOKEN"
  ;;
## --------------------------------------------------------------------------- verify
verify)
  need_tools
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$HERE" || die "cannot enter $HERE"
  [ -s MANIFEST.sha256 ] || die "no MANIFEST.sha256 beside me - this is not a packet directory"
  if ! sha256sum -c MANIFEST.sha256; then
    die "manifest mismatch: the packet was altered or truncated in transit; do not attest"
  fi
  IDENTITY="$(find . -maxdepth 1 -type f -name 'state-recovery-*' -o -maxdepth 1 -type f -name '*recovery*.txt' | head -1)"
  [ -n "$IDENTITY" ] || die "no recovery identity inside the packet"
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
  echo "      challenge decrypted with $(basename "$IDENTITY"); the key in this packet opens both"
  echo
  echo "ATTEST with exactly this line, on the source machine:"
  echo "  ATTEST $TOKEN $got"
  echo
  echo "Then DELETE this packet directory from the machine you copied it to, unless that machine is"
  echo "where you intend the custody copy to live:"
  echo "  find \"\$PWD\" -maxdepth 1 -type f -exec shred -u {} + && rmdir \"\$PWD\""
  ;;
## --------------------------------------------------------------------------- attest (source machine)
attest)
  TOKEN="${1:-}"
  [ -n "$TOKEN" ] || die "usage: scripts/offhost_rehearsal.sh attest <token printed by verify>"
  [ -s "$PENDING" ] || die "no outstanding challenge in $PENDING - run 'pack' first"
  want="$(sed -n 's/^tokenhash=//p' "$PENDING")"
  rec="$(sed -n 's/^recipient=//p' "$PENDING")"
  snap="$(sed -n 's/^snapshot=//p' "$PENDING")"
  issued="$(sed -n 's/^issued=//p' "$PENDING")"
  [ -n "$want" ] || die "outstanding record has no tokenhash - refusing to attest"
  got="$(printf '%s' "$TOKEN" | sha256sum | cut -d' ' -f1)"
  [ "$got" = "$want" ] || die "token does not match the outstanding challenge - not attested"
  { printf 'attested=%s\nrecipient=%s\nsnapshot=%s\nchallenge-issued=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rec" "$snap" "$issued"
    printf 'proof=a nonce encrypted to the recipient was recovered on a machine holding the private half\n'
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
