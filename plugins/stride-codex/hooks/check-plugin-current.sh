#!/usr/bin/env bash
# check-plugin-current.sh — has this stride-codex copy fallen behind the
# published one? stride-workflow Step 0 item 5 calls it at the start of each
# session (W2591, the Codex port of stride W2251).
#
# Codex runs the skills and custom agents from whatever copy is installed, and
# the skills_version on a claim is "1.0" in every release, so the server never
# sees an old copy. This script is the only thing that does.
#
# USAGE: check-plugin-current.sh <skill-dir>
#   <skill-dir> is the folder holding stride-workflow/SKILL.md. Both install
#   shapes put the install root two levels above it:
#     plugin bundle  <root>/.codex-plugin/plugin.json names the version
#     .agents/ copy  <root>/hooks/stride-codex.version, a one-line record that
#                    install.sh and install.ps1 write (a loose copy carries no
#                    plugin.json)
#   The manifest wins when both exist. It counts only when its "name" is
#   "stride-codex", so another plugin's manifest is never read as ours.
#
# PUBLISHED: the "version" of the vendored plugin.json in the
# stride-codex-marketplace catalog, fetched once over HTTPS, accepted only
# when that manifest's "name" is "stride-codex".
#
# OUTPUT: a single line, only when the installed version is lower, carrying
# both numbers and how to update that install shape. Nothing in every other
# case: no argument, neither version source readable, a version made of
# anything but digits and dots (1.40.0-rc.1, v1.40.0 and "latest" are all
# unknown), a part longer than 9 digits, no curl or jq, a failed, slow or
# non-2xx fetch, a body that does not parse, or an installed version equal to
# or newer than the published one. An unknown version is never guessed.
#
# EXIT STATUS: 0 on every path. The line is advice; it never blocks Step 0.
#
# SAFETY: the catalog URL is a constant here, never an input. The fetch is
# anonymous — curl -q first, so no ~/.curlrc can add a header, a netrc login or
# a redirect, and no Authorization header, token or cookie is sent. HTTPS only,
# no redirect followed, 2 seconds to connect and 3 in all. The body is parsed
# by jq as data and never run or sourced; only a string matching VERSION_RE
# (digits and dots, anchored) can reach stdout, so catalog text cannot print
# prose or escape sequences. HOME is never read; curl does still honour the
# proxy and CA-bundle variables of the environment it runs in.
#
# COMPARISON: part by part as base-10 integers, so 1.40.0 is newer than 1.9.0;
# a missing part counts as 0, so 1.40 equals 1.40.0.
#
# Uses bash, curl and jq only: no pipes, no eval, no subshell beyond $( ).

set -u

PIN_URL="https://raw.githubusercontent.com/cheezy/stride-codex-marketplace/main/plugins/stride-codex/.codex-plugin/plugin.json"
UPDATE_BUNDLE="codex plugin update stride-codex"
UPDATE_LOOSE="re-run install.sh, or install.ps1 on Windows (add --project or -Project for a project install)"
VERSION_RE='^[0-9]{1,9}(\.[0-9]{1,9})*$'

# The version from a stride-codex manifest file ($1), or nothing.
manifest_version() {
  [ -f "$1" ] || return 0
  jq -r 'if type == "object" and .name == "stride-codex" and (.version | type) == "string" then .version else empty end' "$1" 2> /dev/null
}

# The first line of the installer's version record ($1), or nothing.
record_version() {
  [ -f "$1" ] || return 0
  IFS= read -r _line < "$1" || [ -n "${_line:-}" ] || return 0
  printf '%s' "${_line%$'\r'}"
}

# Exit 0 only if $1 sorts below $2. The caller has checked both against VERSION_RE.
version_older() {
  IFS=. read -r -a _a <<< "$1"
  IFS=. read -r -a _b <<< "$2"
  _n=${#_a[@]}
  [ "${#_b[@]}" -gt "$_n" ] && _n=${#_b[@]}
  _i=0
  while [ "$_i" -lt "$_n" ]; do
    _x=$(( 10#${_a[$_i]:-0} ))
    _y=$(( 10#${_b[$_i]:-0} ))
    [ "$_x" -lt "$_y" ] && return 0
    [ "$_x" -gt "$_y" ] && return 1
    _i=$(( _i + 1 ))
  done
  return 1
}

main() {
  [ "$#" -ge 1 ] && [ -n "$1" ] || return 0
  command -v jq > /dev/null 2>&1 || return 0
  _root="${1%/}/../.."
  _update="$UPDATE_BUNDLE"
  _installed="$(manifest_version "$_root/.codex-plugin/plugin.json")"
  if [ -z "$_installed" ]; then
    _installed="$(record_version "$_root/hooks/stride-codex.version")"
    _update="$UPDATE_LOOSE"
  fi
  [[ "$_installed" =~ $VERSION_RE ]] || return 0
  command -v curl > /dev/null 2>&1 || return 0
  _body="$(curl -q -sS --fail --proto '=https' --max-redirs 0 --connect-timeout 2 --max-time 3 \
    -A 'curl/stride-codex-plugin-check' "$PIN_URL" 2> /dev/null)" || return 0
  [ -n "$_body" ] || return 0
  _published="$(jq -r 'if type == "object" and .name == "stride-codex" and (.version | type) == "string" then .version else empty end' 2> /dev/null <<< "$_body")"
  [[ "$_published" =~ $VERSION_RE ]] || return 0
  if version_older "$_installed" "$_published"; then
    printf 'stride-codex %s is installed but %s is published - to update: %s\n' \
      "$_installed" "$_published" "$_update"
  fi
  return 0
}

main "$@"
exit 0
