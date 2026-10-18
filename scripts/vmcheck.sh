#!/usr/bin/env bash
# Dev smoke test: build the vmcheck harness, sign it with the virtualization
# entitlement (required even to validate a config), and run it. Proves the real
# VZBackend config path works on this machine without needing an ISO.
#
# Usage:  ./scripts/vmcheck.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product vmcheck
BIN="$(swift build --show-bin-path)/vmcheck"
codesign --force --sign - \
  --entitlements Kapsule/Resources/Kapsule-dev.entitlements "$BIN"
exec "$BIN"
