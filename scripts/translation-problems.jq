# Prints one line per String Catalog entry that lacks a finished Italian translation.
# Used by check-translations.sh. Needs Review counts as finished; "new" and stale do not.

# Every stringUnit under a localization, including plural/device variations and substitutions.
def units: [.. | objects | select(has("stringUnit")) | .stringUnit];

.strings
| to_entries[]
| select(.value.shouldTranslate != false)
| .key as $key
| .value as $entry
| if $entry.extractionState == "stale" then
    "\($key | tojson) is stale (no longer used in code)"
  elif ($entry.localizations.it // null) == null then
    "\($key | tojson) has no Italian translation"
  else
    ($entry.localizations.it | units) as $units
    | if ($units | length) == 0 then
        "\($key | tojson) has an empty Italian entry"
      else
        $units[]
        | select(.state != "translated" and .state != "needs_review")
        | "\($key | tojson) Italian state is \(.state | tojson), expected translated or needs_review"
      end
  end
