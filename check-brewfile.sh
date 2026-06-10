#!/usr/bin/env bash
# Проверяет, что все пакеты из Brewfile существуют в Homebrew,
# не отключены, не устарели и не переименованы.
# Запускается в CI раз в неделю (.github/workflows/check-brewfile.yml),
# можно запустить и локально: ./check-brewfile.sh
set -uo pipefail

cd "$(dirname "$0")"

fail=0

check() {
  local kind="$1" name="$2"
  local key json warnings status
  if [ "$kind" = "formula" ]; then key="formulae"; else key="casks"; fi

  warnings=$(mktemp)
  if ! json=$(brew info --json=v2 "--$kind" "$name" 2>"$warnings"); then
    echo "FAIL  $kind '$name' — не найден в Homebrew"
    sed 's/^/      /' "$warnings"
    fail=1
    return
  fi
  if grep -qi 'renamed' "$warnings"; then
    echo "FAIL  $kind '$name' — переименован, обнови Brewfile:"
    sed 's/^/      /' "$warnings"
    fail=1
    return
  fi

  status=$(echo "$json" | jq -r ".$key[0] | if .disabled then \"disabled\" elif .deprecated then \"deprecated\" else \"ok\" end")
  case "$status" in
    ok)         echo "ok    $kind '$name'" ;;
    deprecated) echo "FAIL  $kind '$name' — deprecated, скоро будет отключён; пора искать замену"; fail=1 ;;
    disabled)   echo "FAIL  $kind '$name' — отключён в Homebrew"; fail=1 ;;
  esac
}

while IFS= read -r name; do check formula "$name"; done < <(sed -n 's/^brew "\([^"]*\)".*/\1/p' Brewfile)
while IFS= read -r name; do check cask "$name"; done < <(sed -n 's/^cask "\([^"]*\)".*/\1/p' Brewfile)

if [ "$fail" -ne 0 ]; then
  echo
  echo "Есть проблемы — см. FAIL выше."
fi
exit "$fail"
