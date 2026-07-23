#!/usr/bin/env bash
# Smoke-test fixture: supply_chain (pipe-to-shell installer)
#
# This script fetches a remote installer over HTTPS and pipes it directly
# into `sh` with no signature check, no checksum, no human approval gate.
# An attacker who compromises the CDN, BGP-hijacks the route, or simply
# updates the upstream installer can land arbitrary code on every CI
# runner that executes this script.

set -euo pipefail

# Bad: install Rust toolchain by piping rustup-init.sh straight into sh.
# The transport (HTTPS) protects against passive eavesdropping but not
# against a compromised upstream.
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Bad: alternate idiom — wget redirecting stdout into bash.
wget -qO- https://get.docker.com | bash

# Bad: PowerShell variant (the rule still fires on these patterns when the
# shell happens to be available — the issue is unverified upstream
# execution, not the specific binary).
# pwsh -Command "iex (irm https://example.com/install.ps1)"

echo "Toolchains installed (allegedly)."
