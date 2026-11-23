#!/usr/bin/env bash
#
# `uca service status` must report a loaded launchd agent as ACTIVE (issue #13).
#
# uca runs under `set -o pipefail`. It used to test `launchctl list | grep -q "$lbl"`;
# grep -q exits at the first match, launchctl dies of SIGPIPE while still writing
# (exit 141), and the pipeline fails, so a loaded agent whose row came early in the
# list was reported as "installed but not loaded".
#
# The test drives the real `uca service status` with a scripted launchctl and uname
# from tests/fixtures/uca-service-status/bin and a fixture HOME. Nothing talks to
# launchd, nothing is written, and it runs the same way on Linux and macOS.
#
# Usage: bash tests/test-uca-service-status.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
uca="$ROOT/uca"
FIX="$ROOT/tests/fixtures/uca-service-status"
fail=0

# uca prepends /usr/local/bin and /opt/homebrew/bin unless they are already on PATH;
# list them after the fixture bin so the fakes keep precedence.
STUB_PATH="$FIX/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# status HOME LOADED_LABEL DOMAIN -> prints `uca service status` output
status() {
  env HOME="$1" USER=ucatest XDG_DATA_HOME="$1/.no-such-data-dir" \
    FAKE_LAUNCHCTL_LOADED="$2" FAKE_LAUNCHCTL_DOMAIN="$3" PATH="$STUB_PATH" \
    bash "$uca" service status 2>&1
}

check() {
  local label=$1 want=$2 got=$3
  if [ "$got" = "$want" ]; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    echo "     want: $want"
    echo "     got:  $got"
    fail=1
  fi
}

active="ACTIVE|launchd background service active (every 3 hours / 10800s)"
not_loaded="INACTIVE|launchd agent installed but not loaded"
not_installed="INACTIVE|launchd agent not installed (run: uca service install)"

# Sanity: the fake launchctl is the one uca will run, and its full listing does
# break a pipefail `grep -q` pipeline the way the real one did.
if [ "$(PATH="$STUB_PATH" command -v launchctl)" != "$FIX/bin/launchctl" ]; then
  echo "FAIL fixture launchctl is not first on PATH"; exit 1
fi
rc=$(set -o pipefail; FAKE_LAUNCHCTL_LOADED=com.ucatest.uca PATH="$STUB_PATH" launchctl list | grep -q com.ucatest.uca; echo $?)
check "fake list pipeline fails under pipefail (as launchctl does)" 141 "$rc"

for i in 1 2 3; do
  check "loaded agent listed first is ACTIVE (run $i)" "$active" "$(status "$FIX/home" com.ucatest.uca both)"
done
check "agent loaded only in the gui domain is ACTIVE" "$active" "$(status "$FIX/home" com.ucatest.uca gui)"
check "installed plist, nothing loaded" "$not_loaded" "$(status "$FIX/home" "" both)"
check "no plist, nothing loaded" "$not_installed" "$(status "$FIX" "" both)"
# The label is matched exactly, not as a regex or a substring of another label.
check "similar label (regex dot) is not ours" "$not_loaded" "$(status "$FIX/home" com.ucatestXuca both)"
check "longer label is not ours" "$not_loaded" "$(status "$FIX/home" com.ucatest.uca.helper both)"

exit "$fail"
