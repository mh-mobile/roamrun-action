#!/usr/bin/env bash
# With ota-server, run.sh runs one `roamrunctl ota` and nothing else; with relay, `install --relay` as before.
# curl serves a release whose roamrunctl only writes down how it was run.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fake=$(mktemp -d)
temp=$(mktemp -d)
failed=0

mkdir -p "$fake/bin" "$fake/release/roamrunctl-linux-x86_64"
cat > "$fake/release/roamrunctl-linux-x86_64/roamrunctl" <<EOF
#!/bin/sh
echo "\$* token=\${ROAMRUNCTL_TOKEN-unset} proxy=\${ROAMRUNCTL_PROXY-unset}" >> "$fake/calls"
EOF
chmod +x "$fake/release/roamrunctl-linux-x86_64/roamrunctl"
(cd "$fake/release" && COPYFILE_DISABLE=1 tar -czf roamrunctl-linux-x86_64.tar.gz roamrunctl-linux-x86_64)
(cd "$fake/release" && if command -v sha256sum >/dev/null; then sha256sum roamrunctl-linux-x86_64.tar.gz
  else shasum -a 256 roamrunctl-linux-x86_64.tar.gz; fi > roamrunctl-SHA256SUMS)
cat > "$fake/bin/curl" <<EOF
#!/bin/sh
while [ \$# -gt 1 ]; do [ "\$1" = -o ] && out=\$2; shift; done
echo "\$1" >> "$fake/urls"
cp "$fake/release/\${1##*/}" "\$out"
EOF
chmod +x "$fake/bin/curl"
: > "$temp/MyApp.ipa"

# run <the calls it should make> <inputs>...
run() {
  local want=$1; shift
  rm -f "$fake/calls"
  local got
  got=$(cd "$temp" && env -i PATH="$fake/bin:$PATH" RUNNER_OS=Linux RUNNER_ARCH=X64 RUNNER_TEMP="$temp" \
    GITHUB_WORKSPACE="$temp" ROAMRUNCTL_PROXY=http://127.0.0.1:1056 RR_KEY= RR_RELAY= RR_TOKEN= \
    RR_OTA_SERVER= RR_OTA_TOKEN= RR_DEVICE= RR_IPA= RR_BUNDLE= RR_LAUNCH=true RR_REPLACE=false RR_TIMEOUT= \
    RR_VERSION=0.12.0 "$@" bash "$here/run.sh" 2>&1)
  local status=$?
  local calls
  calls=$(cat "$fake/calls" 2>/dev/null)
  if [ "$status" -eq 0 ] && [ "$calls" = "$want" ]; then echo "ok: ${want##*$'\n'}"
  else echo "FAIL: wanted calls '$want', got ($status) '$calls': $got"; failed=1; fi
}

ota=(RR_OTA_SERVER=100.64.0.1:9091 RR_OTA_TOKEN=ota-secret RR_IPA=MyApp.ipa)
version="--version token=unset proxy=http://127.0.0.1:1056"
run "$version
ota MyApp.ipa --server 100.64.0.1:9091 token=ota-secret proxy=http://127.0.0.1:1056" "${ota[@]}"
run "$version
ota MyApp.ipa --server 100.64.0.1:9091 --replace --timeout 300 token=ota-secret proxy=http://127.0.0.1:1056" \
  "${ota[@]}" RR_REPLACE=true RR_TIMEOUT=300
run "$version
ota MyApp.ipa --server 100.64.0.1:9091 token=ota-secret proxy=http://127.0.0.1:1056" "${ota[@]}" RR_LAUNCH=false
run "$version
install phone MyApp.ipa --relay 100.64.0.1:9090 --launch token=relay-secret proxy=http://127.0.0.1:1056" \
  RR_RELAY=100.64.0.1:9090 RR_TOKEN=relay-secret RR_DEVICE=phone RR_IPA=MyApp.ipa

if grep -qv '^https://github.com/mh-mobile/RoamRun/releases/download/v0.12.0/' "$fake/urls"; then
  echo "FAIL: fetched from elsewhere: $(cat "$fake/urls")"; failed=1
fi
if [ "$(ls -A "$temp")" != MyApp.ipa ]; then echo "FAIL: left behind: $(ls -A "$temp")"; failed=1; fi
rm -rf "$fake" "$temp"
exit "$failed"
