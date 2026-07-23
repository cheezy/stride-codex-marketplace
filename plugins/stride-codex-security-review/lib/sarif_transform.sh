#!/usr/bin/env bash
#
# sarif_transform.sh — reference implementation of the deterministic transforms
# specified in commands/security-review.md.
#
# The slash command's behavior is specified in prose for an LLM to execute, so
# the deterministic, bug-prone transforms have no executable source of truth.
# This script is that reference implementation: it performs each transform
# EXACTLY as the spec defines it, so run_transform_tests.sh can lock the
# behavior with golden files and explicit value assertions. If this script and
# the prose spec ever disagree, the SPEC is authoritative and this script must
# be corrected to match it (never the reverse).
#
# All transforms are pure: no network, no agent CLI, no secrets. Only `jq` and
# a SHA-256 utility (`sha256sum` or `shasum -a 256`) are required.
#
# Usage:
#   sarif_transform.sh fingerprint <findings.json>   # one lowercase hex hash per finding, in order
#   sarif_transform.sh dedup       <findings.json>   # order-stable dedup by (file,line,vulnerability_class)
#   sarif_transform.sh sarif       <findings.json>   # SARIF v2.1.0 document
#   sarif_transform.sh failon <severity> <findings.json>  # prints N_GATE; exit 1 if >0, else 0
#
# Input shape is the agent's native findings document: {"findings":[ {finding}, ... ], ...}.
#
# Spec references (commands/security-review.md):
#   - Step 4.6  fingerprint = SHA256(vulnerability_class|file|line|first_80_chars_of_description), lowercase hex
#   - Step 4b   dedup merge rule: order-stable, first-occurrence-wins, key (file,line,vulnerability_class)
#   - Step 5    SARIF v2.1.0 mapping (severity->level/security-severity, tags, partialFingerprints)
#   - Step 6    fail-on threshold: critical>high>medium>low>info; info never trips a threshold

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The released version is the `version` key of the Codex plugin manifest.
PLUGIN_JSON="${PLUGIN_JSON:-$SCRIPT_DIR/../.codex-plugin/plugin.json}"

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

require_cmd() {
  command -v jq >/dev/null 2>&1 || die "jq not found on PATH"
}

# sha256_hex — read bytes on stdin, print the lowercase hex SHA-256 digest only.
# Portable across Linux (sha256sum) and macOS (shasum -a 256).
sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    die "no SHA-256 utility found (need sha256sum or shasum)"
  fi
}

# plugin_version — the driver.version SARIF reports; tracks .codex-plugin/plugin.json.
plugin_version() {
  if [ -f "$PLUGIN_JSON" ]; then
    jq -r '.version' "$PLUGIN_JSON"
  else
    printf 'unknown'
  fi
}

# finger_string <findings.json> <index>
# Emits the exact 4-part fingerprint preimage for finding [index], no trailing newline:
#   vulnerability_class|file|line|first_80_chars_of_description
finger_string() {
  jq -rj --argjson i "$2" '
    .findings[$i]
    | ((.vulnerability_class // "") | tostring) + "|"
      + ((.file // "") | tostring) + "|"
      + ((.line // "") | tostring) + "|"
      + (((.description // "") | tostring)[0:80])
  ' "$1"
}

# fingerprint_one <findings.json> <index> — lowercase hex SHA-256 of the preimage.
fingerprint_one() {
  finger_string "$1" "$2" | sha256_hex
}

cmd_fingerprint() {
  local input="$1"
  local n
  n=$(jq '.findings | length' "$input")
  local i
  for ((i = 0; i < n; i++)); do
    fingerprint_one "$input" "$i"
  done
}

cmd_dedup() {
  # Order-stable, first-occurrence-wins, keyed on (file,line,vulnerability_class).
  # reduce preserves input order; `unique_by` would re-sort, so it is NOT used.
  jq '
    {findings:
      (reduce (.findings // [])[] as $f ({seen: {}, out: []};
        ( (($f.file // "") | tostring) + "|"
          + (($f.line // "") | tostring) + "|"
          + (($f.vulnerability_class // "") | tostring) ) as $k
        | if .seen[$k] then .
          else .seen[$k] = true | .out += [$f] end
      ) | .out)
    }
  ' "$1"
}

# rank <severity> — numeric ordering for fail-on. info=0 so it never meets any
# valid threshold (lowest valid threshold is `low`=1).
rank() {
  case "$1" in
    critical) printf '4' ;;
    high)     printf '3' ;;
    medium)   printf '2' ;;
    low)      printf '1' ;;
    info)     printf '0' ;;
    *)        die "invalid severity: $1" ;;
  esac
}

cmd_failon() {
  local threshold="$1" input="$2"
  case "$threshold" in
    critical|high|medium|low) ;;
    *) die "--fail-on requires one of: critical, high, medium, low (got: $threshold)" ;;
  esac
  local tr
  tr=$(rank "$threshold")
  local count
  count=$(jq --argjson tr "$tr" '
    [ (.findings // [])[]
      | .severity
      | (if . == "critical" then 4 elif . == "high" then 3 elif . == "medium" then 2
          elif . == "low" then 1 else 0 end)
      | select(. >= $tr)
    ] | length
  ' "$input")
  printf '%s\n' "$count"
  [ "$count" -gt 0 ] && return 1
  return 0
}

cmd_sarif() {
  local input="$1"
  local version
  version=$(plugin_version)

  # Compute fingerprints in bash (jq has no SHA-256) and hand them to jq by index.
  local n fps
  n=$(jq '.findings | length' "$input")
  fps='[]'
  local i fp
  for ((i = 0; i < n; i++)); do
    fp=$(fingerprint_one "$input" "$i")
    fps=$(printf '%s' "$fps" | jq --arg fp "$fp" '. + [$fp]')
  done

  jq -S --argjson fps "$fps" --arg drv "$version" '
    def level($s):
      if   $s == "critical" then "error"
      elif $s == "high"     then "error"
      elif $s == "medium"   then "warning"
      else "note" end;
    def sevscore($s):
      if   $s == "critical" then "9.0"
      elif $s == "high"     then "7.0"
      elif $s == "medium"   then "5.0"
      elif $s == "low"      then "3.0"
      else "1.0" end;
    (.findings // []) as $f
    | {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [
          {
            "tool": {
              "driver": {
                "name": "stride-codex-security-review",
                "version": $drv,
                "informationUri": "https://github.com/cheezy/stride-codex-security-review",
                "rules": (
                  [ $f[].vulnerability_class ] | unique
                  | map({
                      "id": .,
                      "name": .,
                      "shortDescription": {"text": .},
                      "helpUri": "https://github.com/cheezy/stride-codex-security-review#what-it-catches"
                    })
                )
              }
            },
            "results": (
              [ $f | to_entries[]
                | .key as $i | .value as $x
                | {
                    "ruleId": $x.vulnerability_class,
                    "level": level($x.severity),
                    "message": {"text": ($x.description // "")},
                    "locations": [
                      {
                        "physicalLocation": {
                          "artifactLocation": {"uri": ($x.file // "")},
                          "region": {"startLine": ($x.line // 0)}
                        }
                      }
                    ],
                    "properties": {
                      "tags": (((($x.cwe // []) + ($x.owasp // [])) + ["confidence:" + ($x.confidence // "")])),
                      "security-severity": sevscore($x.severity)
                    },
                    "fixes": [ {"description": {"text": ($x.remediation // "")}} ],
                    "partialFingerprints": {"stride/v1": $fps[$i]}
                  }
              ]
            )
          }
        ]
      }
  ' "$input"
}

main() {
  require_cmd
  [ $# -ge 1 ] || die "usage: sarif_transform.sh <fingerprint|dedup|sarif|failon> ..."
  local mode="$1"; shift
  case "$mode" in
    fingerprint) [ $# -eq 1 ] || die "fingerprint <findings.json>"; cmd_fingerprint "$1" ;;
    dedup)       [ $# -eq 1 ] || die "dedup <findings.json>";       cmd_dedup "$1" ;;
    sarif)       [ $# -eq 1 ] || die "sarif <findings.json>";       cmd_sarif "$1" ;;
    failon)      [ $# -eq 2 ] || die "failon <severity> <findings.json>"; cmd_failon "$1" "$2" ;;
    *)           die "unknown mode: $mode" ;;
  esac
}

main "$@"
