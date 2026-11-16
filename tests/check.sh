#!/bin/bash
# Static checks for the plugin. Runs locally and in CI; needs bash, jq and awk
# (shellcheck and qmllint are used when installed).

# `cond && pass || fail` is safe here: pass() always returns 0, so fail() only runs when cond fails.
# shellcheck disable=SC2015

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

failures=0
pass() { printf '  ok    %s\n' "$1"; return 0; }
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
           $(grep -ohE '"(stream|presets|gateway|manage)\.[a-zA-Z]+"' Service.qml LiveView.qml | tr -d '"' | sort -u); do
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
export XDG_RUNTIME_DIR
XDG_RUNTIME_DIR=$(mktemp -d)
printf 'demo\n' | "$fake" --output json device add "test cam" --host 192.0.2.50:9000 --user admin --password-stdin \
  | jq -e '.ok' >/dev/null && "$fake" --output json device list | jq -e 'any(.data[]; .camera == "test cam")' >/dev/null \
  && "$fake" --output json device remove "test cam" | jq -e '.ok' >/dev/null \
  && pass "device add and remove" || fail "device add and remove"
printf 'wrong\n' | "$fake" --output json --host 192.0.2.50:9000 --user admin --password-stdin login >/dev/null \
  && fail "login accepts a wrong password" || pass "login checks the password from stdin"
"$fake" --output json discover --timeout-secs 1 | jq -e '.data.devices | length > 0 and all(.[]; has("host"))' >/dev/null \
  && pass "discover" || fail "discover"
rm -rf "$XDG_RUNTIME_DIR"
FAKE_EVENT_INTERVAL=0.2 timeout 5 "$fake" --all-devices events stream --timeout 1 \
  | jq -se 'any(.[]; .eventType == "motion" and .data.status == "MD" and (.device | test(":[0-9]+$")))' >/dev/null \
  && pass "events stream" || fail "events stream"

section "Event types"
missing=""
for type in $(grep -oE 'knownTypes: \[[^]]*\]' EventService.qml | grep -oE '"[a-z_]+"' | tr -d '"'); do
  jq -e --arg k "event.$type" 'has($k)' i18n/en.json >/dev/null || missing="$missing event.$type"
  grep -qE "^ +($type: 0x|.*, $type: 0x)" EventService.qml || missing="$missing glyph:$type"
done
[[ -z $missing ]] && pass "every event type has a label and a glyph" || fail "missing:$missing"

shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
lint=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
if [[ -x $lint && -d $shell_dir/Ui ]]; then
  section "QML lint (with Omarchy shell imports)"
  # The shell's modules are named qs.Commons and qs.Ui but live in Commons/ and Ui/,
  # so give qmllint an import path with a qs/ folder that points at them.
  imports=$(mktemp -d)
  trap 'rm -rf "$imports"' EXIT
  mkdir "$imports/qs"
  for module in "$shell_dir"/*/; do
    [[ -f $module/qmldir ]] && ln -s "$module" "$imports/qs/$(basename "$module")"
  done
  # Unqualified access to outer ids is how shell plugins are written, and qmllint cannot
  # see into Style's grouped QtObject properties; every other warning counts.
  if out=$("$lint" -I "$imports" ./*.qml 2>&1 | grep -E '^(Warning|Error)' \
      | grep -v '\[unqualified\]' | grep -v 'not found on type "QObject"'); then
    fail "qmllint: $out"
  else
    pass "qmllint finds no type or property errors"
  fi
fi

if [[ -x $lint ]]; then
  section "QML syntax"
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
