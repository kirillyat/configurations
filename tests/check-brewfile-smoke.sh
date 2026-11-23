#!/usr/bin/env bash
# No downloads/installations: exercise the checker against simulated Brew replies.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
real_jq=$(command -v jq)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/tmp"
printf 'tap "test/tap"\nbrew "wget"\ncask "visual-studio-code"\n' >"$test_dir/Brewfile"

cat >"$test_dir/bin/brew" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "${HOMEBREW_NO_AUTO_UPDATE:-}" = 1 ]] || exit 99
if [[ "$1 $2" = 'bundle list' ]]; then
  [[ "$MOCK_CASE" != parse-failure ]] || { printf 'invalid Brewfile\n' >&2; exit 1; }
  [[ "$MOCK_CASE" != empty-manifest ]] || exit 0
  case "$3" in
    --tap) printf 'test/tap\n' ;;
    --formula) printf 'wget\n' ;;
    --cask) printf 'visual-studio-code\n' ;;
    *) exit 98 ;;
  esac
elif [[ "$1 $2" = 'tap-info --json' ]]; then
  case "$MOCK_CASE" in
    tap-cli-failure) printf 'unknown tap\n' >&2; exit 1 ;;
    tap-empty-json) exit 0 ;;
    tap-invalid-json) printf '{invalid' ;;
    tap-not-installed) printf '[{"name":"test/tap","installed":false}]' ;;
    tap-wrong-name) printf '[{"name":"other/tap","installed":true}]' ;;
    tap-multiple-json) printf '[{"name":"test/tap","installed":true}]\n[{"name":"test/tap","installed":true}]' ;;
    *) printf '[{"name":"test/tap","installed":true}]' ;;
  esac
elif [[ "$1 $2" = 'info --json=v2' ]]; then
  if [[ "$3" = --formula ]]; then key=formulae; else key=casks; fi
  case "$MOCK_CASE" in
    info-cli-failure) printf 'package unavailable\n' >&2; exit 1 ;;
    empty-json) exit 0 ;;
    malformed-json) printf '{invalid' ;;
    missing-key) printf '{}' ;;
    empty-array) printf '{"%s":[]}' "$key" ;;
    multiple-packages) printf '{"%s":[{"disabled":false,"deprecated":false},{"disabled":false,"deprecated":false}]}' "$key" ;;
    multiple-json) printf '{"%s":[{"disabled":false,"deprecated":false}]}\n{"%s":[{"disabled":false,"deprecated":false}]}' "$key" "$key" ;;
    wrong-status-type) printf '{"%s":[{"disabled":"false","deprecated":false}]}' "$key" ;;
    missing-status) printf '{"%s":[{}]}' "$key" ;;
    disabled) printf '{"%s":[{"disabled":true,"deprecated":false}]}' "$key" ;;
    deprecated) printf '{"%s":[{"disabled":false,"deprecated":true}]}' "$key" ;;
    renamed)
      printf 'Warning: package was renamed\n' >&2
      printf '{"%s":[{"disabled":false,"deprecated":false}]}' "$key"
      ;;
    bad-cask)
      [[ "$3" != --cask ]] || exit 0
      printf '{"%s":[{"disabled":false,"deprecated":false}]}' "$key"
      ;;
    *) printf '{"%s":[{"disabled":false,"deprecated":false}]}' "$key" ;;
  esac
else
  printf 'Unexpected brew command: %s\n' "$*" >&2
  exit 98
fi
MOCK

cat >"$test_dir/bin/jq" <<'MOCK'
#!/usr/bin/env bash
[[ "$MOCK_CASE" != jq-failure ]] || exit 7
exec "$REAL_JQ" "$@"
MOCK
chmod +x "$test_dir/bin/brew" "$test_dir/bin/jq"

run_case() {
  local scenario="$1" expected="$2" status=0
  env PATH="$test_dir/bin:$PATH" TMPDIR="$test_dir/tmp" \
    MOCK_CASE="$scenario" REAL_JQ="$real_jq" HOMEBREW_NO_AUTO_UPDATE=0 \
    bash "$repo_dir/check-brewfile.sh" "$test_dir/Brewfile" >"$test_dir/output" 2>&1 || status=$?
  if [[ "$expected" = success && "$status" != 0 ]] || [[ "$expected" = failure && "$status" = 0 ]]; then
    printf 'FAIL: case %s unexpectedly exited %s\n' "$scenario" "$status" >&2
    cat "$test_dir/output" >&2
    exit 1
  fi
  if compgen -G "$test_dir/tmp/configurations-brew-check.*" >/dev/null; then
    printf 'FAIL: temporary files leaked after case %s\n' "$scenario" >&2
    exit 1
  fi
}

run_case good success
for scenario in info-cli-failure empty-json malformed-json missing-key empty-array multiple-packages multiple-json \
  wrong-status-type missing-status disabled deprecated renamed bad-cask jq-failure \
  parse-failure empty-manifest tap-cli-failure tap-empty-json tap-invalid-json \
  tap-not-installed tap-wrong-name tap-multiple-json; do
  run_case "$scenario" failure
done
printf 'Brewfile checker smoke: PASS (23 cases)\n'
