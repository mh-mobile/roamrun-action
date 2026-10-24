#!/usr/bin/env bash
# Each wrong input stops run.sh with its message, before anything is downloaded or sent.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
temp=$(mktemp -d)
failed=0

expect() {
  local want=$1; shift
  local got
  got=$(cd "$temp" && env -i PATH="$PATH" RUNNER_OS="${RUNNER_OS:-Linux}" RUNNER_ARCH="${RUNNER_ARCH:-X64}" \
    RUNNER_TEMP="$temp" GITHUB_WORKSPACE="$temp" RR_KEY= RR_RELAY= ROAMRUNCTL_TOKEN= RR_DEVICE= RR_IPA= \
    RR_BUNDLE= RR_LAUNCH=true RR_TIMEOUT= RR_VERSION=0.9.0 "$@" bash "$here/run.sh" 2>&1)
  local status=$?
  if [ "$status" -ne 0 ] && [ "$got" = "::error::$want" ]; then echo "ok: $want"
  else echo "FAIL: wanted '$want' and a failure, got ($status): $got"; failed=1; fi
}

expect "give key (roamrunctl on this runner) or relay (a relay's address)" RR_BUNDLE=b
expect "give key or relay, not both" RR_KEY=k RR_RELAY=r RR_BUNDLE=b
expect "relay needs token" RR_RELAY=100.64.0.1:9090 RR_DEVICE=d RR_BUNDLE=b
expect "relay needs device: the device as the relay names it" RR_RELAY=100.64.0.1:9090 ROAMRUNCTL_TOKEN=t RR_BUNDLE=b
expect "give ipa (to install) or bundle-id (to launch)" RR_KEY=k
expect "no file at ipa: missing.ipa" RR_KEY=k RR_IPA=missing.ipa
expect "launch is true or false, not maybe" RR_KEY=k RR_BUNDLE=b RR_LAUNCH=maybe
expect "no roamrunctl for Windows on X64 here (Linux and macOS runners only)" RR_KEY=k RR_BUNDLE=b RUNNER_OS=Windows RUNNER_ARCH=X64

if [ -n "$(ls -A "$temp")" ]; then echo "FAIL: something was written: $(ls -A "$temp")"; failed=1; fi
rm -rf "$temp"
exit "$failed"
