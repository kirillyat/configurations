#!/usr/bin/env bash
# Real JSONC helper and installer, isolated HOME, no VS Code/network changes.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
helper_dir="$repo_dir/tools/vscode"
node -e 'if (require(process.argv[1]).version !== "3.3.1") process.exit(1)' \
  "$helper_dir/node_modules/jsonc-parser/package.json"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
test_home="$test_dir/home"
settings="$test_home/Library/Application Support/Code/User/settings.json"
mkdir -p "$(dirname "$settings")" "$test_dir/bin" "$test_dir/backups" "$test_dir/tmp"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_backup_count() {
  local count
  count=$(find "$test_dir/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [[ "$count" = "$1" ]] || fail "Expected $1 backup directories, found $count"
}
while IFS= read -r extension || [[ -n "$extension" ]]; do
  [[ -z "$extension" || "$extension" = \#* ]] && continue
  printf '%s\n' "$extension"
done < "$repo_dir/vscode-extensions.txt" > "$test_dir/extensions.txt"

cat > "$test_dir/bin/code" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$#" = 1 && "$1" = --list-extensions ]]; then
  printf 'list\n' >> "$MOCK_CODE_LOG"
  cat "$MOCK_CODE_EXTENSIONS"
else
  printf 'Unexpected VS Code command: %s\n' "$*" >&2
  exit 87
fi
MOCK
chmod +x "$test_dir/bin/code"
run_install() {
  env HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
    CONFIGURATIONS_BACKUP_ROOT="$test_dir/backups" TMPDIR="$test_dir/tmp" \
    PATH="$test_dir/bin:$PATH" MOCK_CODE_LOG="$test_dir/code.log" \
    MOCK_CODE_EXTENSIONS="$test_dir/extensions.txt" \
    /bin/bash "$repo_dir/install.sh" --dotfiles-only "$@"
}

# Preinstall dotfiles so later backup assertions measure the VS Code operation.
run_install > "$test_dir/dotfiles.log" 2>&1
assert_backup_count 0
cat > "$settings" <<'JSONC'
{
  // Personal settings must survive the selective merge.
  "test.privateDummy": {"token": "dummy-not-a-secret", "url": "https://example.invalid/a//b"},
  "workbench.colorTheme": "My personal theme",
  "python.pythonPath": "/old/python",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.linting.pylintArgs": [
    "--personal" // Preserve the rationale for an obsolete setting.
  ],
  "python.formatting.provider": "autopep8",
  "python.editor.defaultFormatter": "old.formatter",
  "python.formatOnSave": false,
  "[python]": {
    // Keep personal indentation and code actions.
    "editor.tabSize": 2,
    "editor.codeActionsOnSave": {"source.fixAll": "explicit"},
  },
  "terminal.integrated.profiles.osx": {"Personal": {"path": "/bin/zsh", "args": ["-f"]}},
  "code-runner.executorMap": {"javascript": "node"},
}
JSONC
cp "$settings" "$test_dir/original.jsonc"
run_install --with-vscode > "$test_dir/first.log" 2>&1
assert_backup_count 1
backup_settings=$(find "$test_dir/backups" -name settings.json -type f)
[[ -n "$backup_settings" ]] || fail 'Original VS Code settings backup missing'
cmp -s "$backup_settings" "$test_dir/original.jsonc" || fail 'Original settings backup changed'

node - "$settings" "$test_dir/original.jsonc" "$repo_dir/vscode-settings.remove.json" "$helper_dir" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const [settingsPath, originalPath, removePath, helperDir] = process.argv.slice(2);
const { parse } = require(`${helperDir}/node_modules/jsonc-parser`);
function read(file) {
  const errors = [];
  const value = parse(fs.readFileSync(file, 'utf8'), errors, { allowTrailingComma: true });
  assert.deepEqual(errors, []);
  return value;
}
const settings = read(settingsPath);
const original = read(originalPath);
assert.deepEqual(settings['test.privateDummy'], original['test.privateDummy']);
assert.equal(settings['workbench.colorTheme'], 'My personal theme');
assert.equal(settings['[python]']['editor.tabSize'], 2);
assert.equal(settings['[python]']['editor.codeActionsOnSave']['source.fixAll'], 'explicit');
assert.equal(settings['[python]']['editor.defaultFormatter'], 'ms-python.black-formatter');
assert.equal(settings['[python]']['editor.formatOnSave'], true);
assert.equal(settings['python.defaultInterpreterPath'], '${workspaceFolder}/.venv');
assert.equal(settings['black-formatter.importStrategy'], 'useBundled');
assert.deepEqual(settings['terminal.integrated.profiles.osx'].Personal, original['terminal.integrated.profiles.osx'].Personal);
assert.equal(settings['code-runner.executorMap'].javascript, 'node');
for (const key of read(removePath)) assert.equal(Object.hasOwn(settings, key), false);
const text = fs.readFileSync(settingsPath, 'utf8');
assert.ok(text.includes('// Personal settings must survive the selective merge.'));
assert.ok(text.includes('// Keep personal indentation and code actions.'));
assert.ok(text.includes('// Preserve the rationale for an obsolete setting.'));
NODE

cp "$settings" "$test_dir/merged.jsonc"
touch -t 200001010000 "$settings"
settings_metadata=$(stat -f '%i:%m' "$settings")
run_install --with-vscode > "$test_dir/repeated.log" 2>&1
assert_backup_count 1
cmp -s "$settings" "$test_dir/merged.jsonc" || fail 'Repeated merge changed settings bytes'
[[ "$(stat -f '%i:%m' "$settings")" = "$settings_metadata" ]] || fail 'Repeated merge rewrote settings'
[[ "$(wc -l < "$test_dir/code.log" | tr -d ' ')" = 2 ]] || fail 'Unexpected extension activity'

# Parse errors must happen before extension actions or settings backup/write.
printf '{ malformed JSONC\n' > "$settings"
cp "$settings" "$test_dir/malformed.jsonc"
settings_metadata=$(stat -f '%i:%m' "$settings")
cp "$test_dir/code.log" "$test_dir/code-before-failure.log"
if run_install --with-vscode > "$test_dir/invalid.log" 2>&1; then
  fail 'Malformed User settings must fail'
fi
assert_backup_count 1
cmp -s "$settings" "$test_dir/malformed.jsonc" || fail 'Invalid settings were overwritten'
[[ "$(stat -f '%i:%m' "$settings")" = "$settings_metadata" ]] || fail 'Invalid settings metadata changed'
cmp -s "$test_dir/code.log" "$test_dir/code-before-failure.log" || fail 'Extensions changed before validation'
grep -q 'invalid JSONC' "$test_dir/invalid.log" || fail 'Parse error was not reported'
[[ -z "$(find "$test_dir/tmp" -mindepth 1 -print)" ]] || fail 'Temporary settings candidates leaked'
printf 'VS Code installer smoke: PASS\n'
