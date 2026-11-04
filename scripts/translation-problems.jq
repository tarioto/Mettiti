# Prints one line per String Catalog problem: a missing, unfinished, empty or malformed Italian
# translation, or a stale key. Used by check-translations.sh. Needs Review counts as finished.

# Every stringUnit under a localization, including plural/device variations and substitutions.
def units: [.. | objects | select(has("stringUnit")) | .stringUnit];

# Format specifiers in a string, normalized and sorted so they compare as a multiset:
# positional forms (%1$@) count as their plain form (%@), and %% is not a placeholder.
def placeholders:
  [scan("%%|%#@[A-Za-z0-9_]+@|%(?:[0-9]+\\$)?[-+ #0']*(?:[0-9]+|\\*)?(?:\\.(?:[0-9]+|\\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSaAp]")
   | select(. != "%%")
   | sub("^%[0-9]+\\$"; "%")]
  | sort;

# The Italian values whose placeholders must match the English: plain and device-variant units
# and plural "other" forms. Other plural forms (e.g. "one") may drop the number, and units inside
# substitutions use their own argument syntax.
def comparable_values:
  path(.. | objects | select(has("stringUnit"))) as $path
  | select(($path | index("substitutions")) == null)
  | select(($path | index("plural")) as $i | $i == null or $path[$i + 1] == "other")
  | getpath($path).stringUnit.value // empty;

if (.strings | type) != "object" then error("catalog has no strings object") else . end
| .strings
| to_entries[]
| .key as $key
| .value as $entry
# Stale is checked before shouldTranslate: an unused key is a problem whether or not it's translated.
| if $entry.extractionState == "stale" then
    "\($key | tojson) is stale (no longer used in code)"
  elif $entry.shouldTranslate == false then
    empty
  elif ($entry.localizations.it // null) == null then
    "\($key | tojson) has no Italian translation"
  else
    $entry.localizations.it as $it
    | ($it | units) as $units
    | if ($units | length) == 0 then
        "\($key | tojson) has an empty Italian entry"
      else
        ($it | .. | objects | select(has("plural")) | .plural
          | select(has("other") | not)
          | "\($key | tojson) has an Italian plural without an other form"),
        ($units[]
          | select(.state != "translated" and .state != "needs_review")
          | "\($key | tojson) Italian state is \(.state | tojson), expected translated or needs_review"),
        ($units[]
          | select((.value // "") == "")
          | "\($key | tojson) has an empty Italian value"),
        (($entry.localizations.en.stringUnit.value
            // $entry.localizations.en.variations.plural.other.stringUnit.value
            // $key | placeholders) as $english
          | $it | comparable_values
          | select(. != "")
          | placeholders as $italian
          | select($italian != $english)
          | "\($key | tojson) Italian placeholders \($italian | tojson) differ from English \($english | tojson)")
      end
  end
