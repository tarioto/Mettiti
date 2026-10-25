#!/usr/bin/env bash
# Fail if any String Catalog entry lacks a finished Italian translation or is stale.
#
# Entries marked "Needs Review" pass: machine-translated Italian is fine for TestFlight.
# Only "Translated" is required before an App Store submission, and that is a human gate
# (see README), not enforced here.
#
# Usage: scripts/check-translations.sh [catalog.xcstrings ...]
# With no arguments, checks every .xcstrings file tracked by git.
set -euo pipefail

if [[ $# -gt 0 ]]; then
  catalogs=("$@")
else
  catalogs=()
  while IFS= read -r path; do catalogs+=("$path"); done < <(git ls-files '*.xcstrings')
fi

if [[ ${#catalogs[@]} -eq 0 ]]; then
  echo "No String Catalogs found." >&2
  exit 1
fi

filter="$(dirname "$0")/translation-problems.jq"

failures=0
for catalog in "${catalogs[@]}"; do
  while IFS= read -r message; do
    echo "::error file=$catalog::$message"
    failures=$((failures + 1))
  done < <(jq -r -f "$filter" "$catalog")
done

if [[ $failures -gt 0 ]]; then
  echo "$failures translation problem(s)." >&2
  exit 1
fi
echo "Checked ${#catalogs[@]} catalog(s): every key has an Italian translation."
