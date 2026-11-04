#!/usr/bin/env bash
# Runs check-translations.sh against the fixtures in scripts/fixtures/ and checks each verdict.
# The clean catalog must pass; every other case must fail and report the expected problem.
#
# Usage: scripts/test-check-translations.sh
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check-translations.sh"
fixtures="$here/fixtures"
failed=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2"; failed=$((failed + 1)); }

# The clean catalog passes.
if output=$("$check" "$fixtures/clean.xcstrings" 2>&1); then
  pass "clean.xcstrings passes"
else
  fail "clean.xcstrings passes" "exited non-zero:"$'\n'"$output"
fi

# Each case: catalog path | text the output must contain.
cases=(
  "$fixtures/does-not-exist.xcstrings|could not read"
  "$fixtures/malformed-json.xcstrings|could not read"
  "$fixtures/no-strings.xcstrings|has no strings object"
  "$fixtures/stale-not-translated.xcstrings|\"OldBase\" is stale"
  "$fixtures/empty-value.xcstrings|\"Hello\" has an empty Italian value"
  "$fixtures/plural-without-other.xcstrings|\"%lld hours\" has an Italian plural without an other form"
  "$fixtures/placeholder-mismatch.xcstrings|\"Fmt %@ %lld\" Italian placeholders"
)

for case in "${cases[@]}"; do
  catalog="${case%%|*}"
  expected="${case#*|}"
  name="$(basename "$catalog")"
  if output=$("$check" "$catalog" 2>&1); then
    fail "$name fails" "exited 0:"$'\n'"$output"
  elif [[ "$output" != *"$expected"* ]]; then
    fail "$name fails" "output lacks \"$expected\":"$'\n'"$output"
  else
    pass "$name fails"
  fi
done

if [[ $failed -gt 0 ]]; then
  echo "$failed check(s) failed." >&2
  exit 1
fi
echo "All checks passed."
