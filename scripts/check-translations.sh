#!/usr/bin/env bash
# Fail if a String Catalog can't be read, or any entry is stale or lacks a finished, well-formed
# Italian translation (see translation-problems.jq for the rules).
#
# Entries marked "Needs Review" pass: machine-translated Italian is fine for TestFlight.
# Only "Translated" is required before an App Store submission, and that is a human gate
# (see README), not enforced here.
#
# Usage: scripts/check-translations.sh [catalog.xcstrings ...]
# With no arguments, checks every .xcstrings file tracked by git, except the test fixtures.
set -euo pipefail

if [[ $# -gt 0 ]]; then
  catalogs=("$@")
else
  catalogs=()
  while IFS= read -r path; do catalogs+=("$path"); done < <(git ls-files '*.xcstrings' ':!scripts/fixtures/')
fi

if [[ ${#catalogs[@]} -eq 0 ]]; then
  echo "No String Catalogs found." >&2
  exit 1
fi

filter="$(dirname "$0")/translation-problems.jq"

failures=0
for catalog in "${catalogs[@]}"; do
  # Capture rather than pipe: a jq failure inside process substitution escapes set -e.
  if ! problems=$(jq -r -f "$filter" "$catalog" 2>&1); then
    echo "::error file=$catalog::could not read catalog: ${problems//$'\n'/ }"
    failures=$((failures + 1))
    continue
  fi
  while IFS= read -r message; do
    [[ -n "$message" ]] || continue
    echo "::error file=$catalog::$message"
    failures=$((failures + 1))
  done <<< "$problems"
done

if [[ $failures -gt 0 ]]; then
  echo "$failures translation problem(s)." >&2
  exit 1
fi
echo "Checked ${#catalogs[@]} catalog(s): every key has an Italian translation."
