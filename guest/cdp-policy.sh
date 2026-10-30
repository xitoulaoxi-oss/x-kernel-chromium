#!/bin/sh
# Diagnostic-only: xkwin permits this script only with a QEMU snapshot.
set -eu
f=/etc/chromium/policies/managed/kiosk.json
if [ ! -r "$f" ]; then
  echo CDP_POLICY_ABSENT
  exit 0
fi
cp "$f" /tmp/xk-cdp-policy-original.json
echo CDP_POLICY_BEFORE
sha256sum "$f"
grep 'DeveloperToolsAvailability' "$f" || true
sed -i 's/"DeveloperToolsAvailability"[[:space:]]*:[[:space:]]*2\([[:space:]]*[,}]\)/"DeveloperToolsAvailability": 1\1/' "$f"
echo CDP_POLICY_AFTER
sha256sum "$f"
grep 'DeveloperToolsAvailability' "$f" || true
echo CDP_POLICY_SCOPE=QEMU_SNAPSHOT
