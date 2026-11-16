#!/bin/bash
# Static checks for the plugin. Runs locally and in CI; needs bash, jq and awk
# (shellcheck and qmllint are used when installed).

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
section() { printf '\n%s\n' "$1"; }

section "Manifest"
if jq -e . manifest.json >/dev/null 2>&1; then pass "manifest.json is valid JSON"; else fail "manifest.json is not valid JSON"; fi
jq -e '.schemaVersion == 1' manifest.json >/dev/null && pass "schemaVersion is 1" || fail "schemaVersion must be the number 1"
for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' manifest.json >/dev/null || fail "missing field: $field"
done
id=$(jq -r .id manifest.json)
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != omarchy.* ]] && pass "id '$id' is allowed" || fail "invalid id '$id'"
jq -r '.version' manifest.json | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' && pass "version is semver" || fail "version is not semver"
while IFS= read -r entry; do
  [[ -f $entry && $entry != /* && $entry != *..* ]] && pass "entry point $entry exists" || fail "bad entry point: $entry"
done < <(jq -r '.entryPoints[]' manifest.json)
if [[ -z $(find . -path ./.git -prune -o -type l -print) ]]; then pass "no symlinks"; else fail "symlinks are rejected by omarchy plugin validate"; fi
grep -q "\"$id\"" Panel.qml && pass "Panel.qml moduleName matches id" || fail "Panel.qml moduleName does not match manifest id"

section "Translations"
en_keys=$(jq -r 'keys[]' i18n/en.json | sort)
for f in i18n/*.json; do
  if ! jq -e . "$f" >/dev/null 2>&1; then fail "$f is not valid JSON"; continue; fi
  diff_out=$(diff <(echo "$en_keys") <(jq -r 'keys[]' "$f" | sort))
  [[ -z $diff_out ]] && pass "$f has the same keys as en.json" || fail "$f keys differ from en.json: $(echo "$diff_out" | tr '\n' ' ')"
done
missing=""
for key in $(grep -ohE 'tr\("[A-Za-z.]+"' ./*.qml | sed -E 's/tr\("//; s/"$//' | sort -u) \
           $(grep -ohE '"(stream|presets|gateway)\.[a-zA-Z]+"' Service.qml LiveView.qml | tr -d '"' | sort -u); do
  jq -e --arg k "$key" 'has($k)' i18n/en.json >/dev/null || missing="$missing $key"
done
[[ -z $missing ]] && pass "every key used in QML exists in en.json" || fail "keys missing from en.json:$missing"

section "Untrusted text"
# Every Text element must render plain text, so device-provided names cannot inject markup.
for f in ./*.qml; do
  texts=$(grep -cE '^\s*Text \{' "$f")
  plain=$(grep -cE 'textFormat: Text\.PlainText' "$f")
  (( plain >= texts )) && pass "$(basename "$f"): $texts Text element(s), all PlainText" \
    || fail "$(basename "$f"): $texts Text elements but only $plain set textFormat: Text.PlainText"
done
if grep -nE 'execDetached\(\["(sh|bash)", "-c", "[^"]*" \+' ./*.qml; then
  fail "shell code is built by string concatenation; pass values as positional arguments"
else
  pass "no values concatenated into shell code"
fi

section "Shell scripts"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck setup tests/check.sh tests/fake-reolink-cli && pass "shellcheck" || fail "shellcheck"
else
  printf '  skip  shellcheck not installed\n'
fi
for s in setup tests/check.sh tests/fake-reolink-cli; do
  [[ -x $s ]] && pass "$s is executable" || fail "$s is not executable"
done

section "Fake CLI contract"
fake=tests/fake-reolink-cli
"$fake" --output json device list | jq -e '.ok and (.data | type == "array") and all(.data[]; has("camera"))' >/dev/null \
  && pass "device list" || fail "device list"
"$fake" --output json gateway status | jq -e '.data.listening == true' >/dev/null && pass "gateway status" || fail "gateway status"
"$fake" --output json --camera garden ptz preset list | jq -e '.data.presets | length > 0' >/dev/null \
  && pass "ptz preset list" || fail "ptz preset list"

if command -v qmllint >/dev/null 2>&1 || [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  section "QML syntax"
  lint=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
  # The qs.* shell modules only exist inside omarchy-shell, so only syntax errors count here.
  if out=$("$lint" ./*.qml 2>&1 | grep -iE 'syntax error|Expected token|Unexpected token'); then
    fail "qmllint: $out"
  else
    pass "qmllint finds no syntax errors"
  fi
fi

printf '\n'
if (( failures )); then
  printf '%d check(s) failed\n' "$failures"
  exit 1
fi
printf 'All checks passed\n'
