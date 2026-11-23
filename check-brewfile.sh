#!/usr/bin/env bash
# Проверяет наличие, переименования и статус пакетов из Brewfile.
# Ничего не устанавливает. Для свежих метаданных сначала запусти brew update.
set -euo pipefail

cd "$(dirname "$0")"
export HOMEBREW_NO_AUTO_UPDATE=1

if [ "$#" -gt 1 ]; then
  printf 'Usage: %s [Brewfile]\n' "$0" >&2
  exit 2
fi
brewfile="${1:-Brewfile}"
for tool in brew jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'FAIL  Required command not found: %s\n' "$tool" >&2
    exit 1
  fi
done
if [ ! -f "$brewfile" ]; then
  printf 'FAIL  Brewfile not found: %s\n' "$brewfile" >&2
  exit 1
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/configurations-brew-check.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail=0
entries=0

diagnostics() {
  sed 's/^/      /' "$tmpdir/warnings"
}

check_package() {
  local kind="$1" name="$2" key status
  if [ "$kind" = formula ]; then key=formulae; else key=casks; fi

  if ! brew info --json=v2 "--$kind" "$name" >"$tmpdir/info.json" 2>"$tmpdir/warnings"; then
    printf "FAIL  %s '%s' — brew info failed\n" "$kind" "$name"
    diagnostics
    fail=1
    return
  fi
  if grep -qi renamed "$tmpdir/warnings"; then
    printf "FAIL  %s '%s' — renamed; update Brewfile\n" "$kind" "$name"
    diagnostics
    fail=1
    return
  fi

  # jq must fail on empty output, invalid JSON and missing/invalid metadata.
  # Without schema checks, null.disabled would otherwise be treated as false.
  if ! status=$(jq -ser --arg key "$key" '
    if length != 1 then error("expected exactly one JSON document") else .[0] end
    | if type != "object" then error("expected a JSON object")
    else .[$key] end
    | if type != "array" then error("expected a package array")
      elif length != 1 then error("expected exactly one package")
      else .[0] end
    | if type != "object" then error("expected a package object")
      elif (.disabled | type) != "boolean" or (.deprecated | type) != "boolean"
        then error("missing or invalid package status")
      elif .disabled then "disabled"
      elif .deprecated then "deprecated"
      else "ok" end
  ' "$tmpdir/info.json" 2>"$tmpdir/warnings"); then
    printf "FAIL  %s '%s' — invalid Homebrew JSON\n" "$kind" "$name"
    diagnostics
    fail=1
    return
  fi
  case "$status" in
    ok) printf "ok    %s '%s'\n" "$kind" "$name" ;;
    disabled|deprecated)
      printf "FAIL  %s '%s' — %s\n" "$kind" "$name" "$status"
      fail=1
      ;;
    *)
      printf "FAIL  %s '%s' — unexpected status: %s\n" "$kind" "$name" "$status"
      fail=1
      ;;
  esac
}

check_tap() {
  local name="$1"
  if ! brew tap-info --json "$name" >"$tmpdir/info.json" 2>"$tmpdir/warnings"; then
    printf "FAIL  tap '%s' — brew tap-info failed\n" "$name"
    diagnostics
    fail=1
    return
  fi
  if ! jq -se --arg name "$name" '
    if length != 1 then error("expected exactly one JSON document") else .[0] end
    | if type != "array" then false
    elif length != 1 then false
    else .[0].name == $name and .[0].installed == true end
  ' "$tmpdir/info.json" >/dev/null 2>"$tmpdir/warnings"; then
    printf "FAIL  tap '%s' — invalid metadata or tap is not installed; run brew tap first\n" "$name"
    diagnostics
    fail=1
    return
  fi
  printf "ok    tap '%s'\n" "$name"
}

# Let Homebrew parse Ruby, including indentation, single quotes and options.
# A failed parser must not disappear inside an unchecked process substitution.
for kind in tap formula cask; do
  if ! brew bundle list "--$kind" "--file=$brewfile" >"$tmpdir/$kind.list" 2>"$tmpdir/warnings"; then
    printf 'FAIL  Cannot parse %s entries in %s\n' "$kind" "$brewfile"
    diagnostics
    exit 1
  fi
  while IFS= read -r name || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    entries=$((entries + 1))
    if [ "$kind" = tap ]; then check_tap "$name"; else check_package "$kind" "$name"; fi
  done <"$tmpdir/$kind.list"
done

if [ "$entries" -eq 0 ]; then
  printf 'FAIL  No brew, cask or tap entries found in %s\n' "$brewfile"
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  printf '\nBrewfile has problems; see FAIL above.\n'
fi
exit "$fail"
