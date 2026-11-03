#!/usr/bin/env bash
# Installs and launches on a device with roamrunctl: on this runner (RR_KEY) or through a relay (RR_RELAY).
# With RR_OTA_SERVER, publishes the .ipa to a Mac's OTA page through its OTA server instead.
set -euo pipefail

fail() { echo "::error::$1"; exit 1; }

# What was asked, checked before anything is fetched or sent.
case "$RR_REPLACE" in true|false) ;; *) fail "replace is true or false, not $RR_REPLACE" ;; esac
if [ -n "$RR_OTA_SERVER" ]; then
  if [ -n "$RR_KEY" ] || [ -n "$RR_RELAY" ]; then fail "ota-server publishes to the OTA page: give it without key or relay"; fi
  if [ -n "$RR_TOKEN" ]; then fail "the OTA server's token goes in ota-server-token, not token"; fi
  if [ -n "$RR_DEVICE" ] || [ -n "$RR_BUNDLE" ]; then fail "ota-server installs on no device: give it without device or bundle-id"; fi
  if [ -z "$RR_OTA_TOKEN" ]; then fail "ota-server needs ota-server-token"; fi
  if [ -z "$RR_IPA" ]; then fail "ota-server needs ipa: the .ipa to publish"; fi
  if [ ! -f "$RR_IPA" ]; then fail "no file at ipa: $RR_IPA"; fi
  if [[ ! "$RR_VERSION" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+ ]] \
    || { [ "${BASH_REMATCH[1]}" -eq 0 ] && [ "${BASH_REMATCH[2]}" -lt 12 ]; }; then
    fail "ota-server needs roamrunctl-version 0.12.0 or later, not $RR_VERSION"
  fi
else
  if [ -n "$RR_OTA_TOKEN" ]; then fail "ota-server-token goes with ota-server"; fi
  if [ "$RR_REPLACE" = true ]; then fail "replace goes with ota-server"; fi
  if [ -n "$RR_KEY" ] && [ -n "$RR_RELAY" ]; then fail "give key or relay, not both"; fi
  if [ -z "$RR_KEY" ] && [ -z "$RR_RELAY" ]; then
    fail "give key (roamrunctl on this runner), relay (a relay's address) or ota-server (an OTA server's address)"
  fi
  if [ -n "$RR_RELAY" ] && [ -z "$RR_TOKEN" ]; then fail "relay needs token"; fi
  if [ -n "$RR_RELAY" ] && [ -z "$RR_DEVICE" ]; then fail "relay needs device: the device as the relay names it"; fi
  if [ -z "$RR_IPA" ] && [ -z "$RR_BUNDLE" ]; then fail "give ipa (to install) or bundle-id (to launch)"; fi
  if [ -n "$RR_IPA" ] && [ ! -f "$RR_IPA" ]; then fail "no file at ipa: $RR_IPA"; fi
  case "$RR_LAUNCH" in true|false) ;; *) fail "launch is true or false, not $RR_LAUNCH" ;; esac
fi

case "$RUNNER_OS/$RUNNER_ARCH" in
  Linux/X64) archive=roamrunctl-linux-x86_64 ;;
  Linux/ARM64) archive=roamrunctl-linux-aarch64 ;;
  macOS/ARM64) archive=roamrunctl-macos-aarch64 ;;
  macOS/X64) archive=roamrunctl-macos-x86_64 ;;
  *) fail "no roamrunctl for $RUNNER_OS on $RUNNER_ARCH here (Linux and macOS runners only)" ;;
esac

# Everything this writes, the key's file among them, is in a folder of its own, removed at the end.
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/roamrun-action.XXXXXX")
trap 'rm -rf "$work"' EXIT
cd "$work"
base="https://github.com/mh-mobile/RoamRun/releases/download/v$RR_VERSION"
curl -fsSL --retry 3 -o "$archive.tar.gz" "$base/$archive.tar.gz"
curl -fsSL --retry 3 -o SHA256SUMS "$base/roamrunctl-SHA256SUMS"
grep " $archive.tar.gz\$" SHA256SUMS > want || fail "$archive.tar.gz isn't in roamrunctl-SHA256SUMS of v$RR_VERSION"
if command -v sha256sum >/dev/null; then sha256sum -c want; else shasum -a 256 -c want; fi
tar -xzf "$archive.tar.gz" --strip-components 1 "$archive/roamrunctl"
rr="$work/roamrunctl"
"$rr" --version
cd "$GITHUB_WORKSPACE"

# The options each command takes (none on this runner); written out, as bash 3.2 (macOS's) refuses
# an empty array under set -u.
if [ -n "$RR_OTA_SERVER" ]; then
  export ROAMRUNCTL_TOKEN=$RR_OTA_TOKEN
  do_ota() {
    if [ -n "$RR_TIMEOUT" ]; then "$rr" ota "$RR_IPA" --server "$RR_OTA_SERVER" "$@" --timeout "$RR_TIMEOUT"
    else "$rr" ota "$RR_IPA" --server "$RR_OTA_SERVER" "$@"; fi
  }
  if [ "$RR_REPLACE" = true ]; then do_ota --replace; else do_ota; fi
  exit 0
fi
export ROAMRUNCTL_TOKEN=$RR_TOKEN
if [ -n "$RR_KEY" ]; then
  export XDG_CONFIG_HOME="$work/config"
  umask 077
  name=${RR_DEVICE:-device}
  printf '%s' "$RR_KEY" | "$rr" key import - --as "$name"
  do_install() { "$rr" install "$name" "$RR_IPA" "$@"; }
  do_launch() { "$rr" launch "$name" "$RR_BUNDLE"; }
else
  name=$RR_DEVICE
  do_install() {
    if [ -n "$RR_TIMEOUT" ]; then "$rr" install "$name" "$RR_IPA" --relay "$RR_RELAY" --timeout "$RR_TIMEOUT" "$@"
    else "$rr" install "$name" "$RR_IPA" --relay "$RR_RELAY" "$@"; fi
  }
  do_launch() { "$rr" launch "$name" "$RR_BUNDLE" --relay "$RR_RELAY"; }
fi

if [ -n "$RR_IPA" ]; then
  if [ "$RR_LAUNCH" = true ] && [ -z "$RR_BUNDLE" ]; then do_install --launch; else do_install; fi
fi
if [ -n "$RR_BUNDLE" ] && { [ -z "$RR_IPA" ] || [ "$RR_LAUNCH" = true ]; }; then do_launch; fi
