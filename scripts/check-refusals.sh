#!/usr/bin/env bash
# Each wrong input stops run.sh with its message, before anything is downloaded or sent.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
temp=$(mktemp -d)
ipas=$(mktemp -d)
ipa="$ipas/MyApp.ipa"
: > "$ipa"
failed=0

expect() {
  local want=$1; shift
  local got
  got=$(cd "$temp" && env -i PATH="$PATH" RUNNER_OS="${RUNNER_OS:-Linux}" RUNNER_ARCH="${RUNNER_ARCH:-X64}" \
    RUNNER_TEMP="$temp" GITHUB_WORKSPACE="$temp" RR_KEY= RR_RELAY= RR_TOKEN= RR_OTA_SERVER= RR_OTA_TOKEN= \
    RR_DEVICE= RR_IPA= RR_BUNDLE= RR_LAUNCH=true RR_REPLACE=false RR_TIMEOUT= RR_VERSION=0.9.0 "$@" bash "$here/run.sh" 2>&1)
  local status=$?
  if [ "$status" -ne 0 ] && [ "$got" = "::error::$want" ]; then echo "ok: $want"
  else echo "FAIL: wanted '$want' and a failure, got ($status): $got"; failed=1; fi
}

expect "give key (roamrunctl on this runner), relay (a relay's address) or ota-server (an OTA server's address)" RR_BUNDLE=b
expect "give key or relay, not both" RR_KEY=k RR_RELAY=r RR_BUNDLE=b
expect "relay needs token" RR_RELAY=100.64.0.1:9090 RR_DEVICE=d RR_BUNDLE=b
expect "relay needs device: the device as the relay names it" RR_RELAY=100.64.0.1:9090 RR_TOKEN=t RR_BUNDLE=b
expect "give ipa (to install) or bundle-id (to launch)" RR_KEY=k
expect "no file at ipa: missing.ipa" RR_KEY=k RR_IPA=missing.ipa
expect "launch is true or false, not maybe" RR_KEY=k RR_BUNDLE=b RR_LAUNCH=maybe
expect "no roamrunctl for Windows on X64 here (Linux and macOS runners only)" RR_KEY=k RR_BUNDLE=b RUNNER_OS=Windows RUNNER_ARCH=X64

# The OTA server: inputs for a device are refused, and so are its own without it.
ota=(RR_OTA_SERVER=100.64.0.1:9091 RR_OTA_TOKEN=o RR_VERSION=0.12.0)
expect "ota-server publishes to the OTA page: give it without key or relay" "${ota[@]}" RR_IPA="$ipa" RR_KEY=k
expect "ota-server publishes to the OTA page: give it without key or relay" "${ota[@]}" RR_IPA="$ipa" RR_RELAY=r
expect "the OTA server's token goes in ota-server-token, not token" "${ota[@]}" RR_IPA="$ipa" RR_TOKEN=t
expect "ota-server installs on no device: give it without device or bundle-id" "${ota[@]}" RR_IPA="$ipa" RR_DEVICE=d
expect "ota-server installs on no device: give it without device or bundle-id" "${ota[@]}" RR_IPA="$ipa" RR_BUNDLE=b
expect "ota-server needs ota-server-token" "${ota[@]}" RR_IPA="$ipa" RR_OTA_TOKEN=
expect "ota-server needs ipa: the .ipa to publish" "${ota[@]}"
expect "no file at ipa: missing.ipa" "${ota[@]}" RR_IPA=missing.ipa
expect "replace is true or false, not yes" "${ota[@]}" RR_IPA="$ipa" RR_REPLACE=yes
expect "ota-server needs roamrunctl-version 0.12.0 or later, not 0.11.0" "${ota[@]}" RR_IPA="$ipa" RR_VERSION=0.11.0
expect "ota-server needs roamrunctl-version 0.12.0 or later, not latest" "${ota[@]}" RR_IPA="$ipa" RR_VERSION=latest
expect "ota-server-token goes with ota-server" RR_KEY=k RR_IPA="$ipa" RR_OTA_TOKEN=o
expect "replace goes with ota-server" RR_KEY=k RR_IPA="$ipa" RR_REPLACE=true

if [ -n "$(ls -A "$temp")" ]; then echo "FAIL: something was written: $(ls -A "$temp")"; failed=1; fi
rm -rf "$temp" "$ipas"
exit "$failed"
