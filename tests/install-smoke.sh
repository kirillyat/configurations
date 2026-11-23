#!/usr/bin/env bash
# Integration test: copy/symlink modes, original data and repeated installation.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
test_home="$test_dir/home"
mkdir -p "$test_home/.config/uv" "$test_home/.gitignore_global"
printf 'original zshrc\n' > "$test_home/.zshrc"
printf 'original uv config\n' > "$test_home/.config/uv/uv.toml"
printf 'original git config\n' > "$test_dir/external-gitconfig"
printf 'original directory data\n' > "$test_home/.gitignore_global/keep.txt"
ln -s /missing/original-vimrc "$test_home/.vimrc"
ln -s "$test_dir/external-gitconfig" "$test_home/.gitconfig"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_copy() {
  local dst="$1" src="$2"
  [[ -f "$dst" && ! -L "$dst" ]] || fail "Expected regular copy: $dst"
  cmp -s "$dst" "$src" || fail "Copy differs from source: $dst"
}
assert_link() {
  local dst="$1" src="$2"
  [[ -L "$dst" ]] || fail "Expected symlink: $dst"
  [[ "$(readlink "$dst")" = "$src" ]] || fail "Wrong symlink target: $dst"
}
assert_installation() {
  local mode="$1" name
  for name in .zprofile .zshrc .vimrc .gitconfig .gitignore_global; do
    "assert_$mode" "$test_home/$name" "$repo_dir/$name"
  done
  "assert_$mode" "$test_home/.config/uv/uv.toml" "$repo_dir/config/uv/uv.toml"
}
assert_backup_count() {
  local expected="$1" count
  count=$(find "$test_dir/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [[ "$count" = "$expected" ]] || fail "Expected $expected backup directories, found $count"
}
run_install() {
  env HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
    CONFIGURATIONS_BACKUP_ROOT="$test_dir/backups" \
    /bin/bash "$repo_dir/install.sh" --dotfiles-only "$@"
}
run_install
assert_installation copy
assert_backup_count 1
backup_count=$(find "$test_dir/backups" -name .zshrc -type f | wc -l | tr -d ' ')
[[ "$backup_count" = 1 ]] || fail 'Expected one original zshrc backup'
backup_zshrc=$(find "$test_dir/backups" -name .zshrc -type f)
original_backup=$(dirname "$backup_zshrc")
[[ "$(cat "$backup_zshrc")" = 'original zshrc' ]] || fail 'Original zshrc lost'
assert_link "$original_backup/.vimrc" /missing/original-vimrc
assert_link "$original_backup/.gitconfig" "$test_dir/external-gitconfig"
[[ "$(cat "$test_dir/external-gitconfig")" = 'original git config' ]] || fail 'Symlink target changed'
[[ "$(cat "$original_backup/.gitignore_global/keep.txt")" = 'original directory data' ]] || fail 'Original directory lost'
[[ "$(cat "$original_backup/.config/uv/uv.toml")" = 'original uv config' ]] || fail 'Original uv config lost'

# Identical copies must keep both metadata and backup count on another run.
touch -t 200001010000 "$test_home/.zshrc"
copy_metadata=$(stat -f '%i:%m' "$test_home/.zshrc")
run_install
assert_installation copy
assert_backup_count 1
[[ "$(stat -f '%i:%m' "$test_home/.zshrc")" = "$copy_metadata" ]] || fail 'Identical copy was rewritten'

# Opting into links backs up the copies; another link run is a no-op.
run_install --symlink
assert_installation link
assert_backup_count 2
[[ "$(find "$test_dir/backups" -name .zshrc -type f | wc -l | tr -d ' ')" = 2 ]] || fail 'Copy backup missing'
link_metadata=$(stat -f '%i:%m' "$test_home/.zshrc")
run_install --symlink
assert_installation link
assert_backup_count 2
[[ "$(stat -f '%i:%m' "$test_home/.zshrc")" = "$link_metadata" ]] || fail 'Identical link was rewritten'

# Returning to defaults converts links into independent files, preserving links.
run_install
assert_installation copy
assert_backup_count 3
backup_link=$(find "$test_dir/backups" -name .zshrc -type l)
assert_link "$backup_link" "$repo_dir/.zshrc"
touch -t 200001010000 "$test_home/.zshrc"
copy_metadata=$(stat -f '%i:%m' "$test_home/.zshrc")
run_install
assert_installation copy
assert_backup_count 3
[[ "$(stat -f '%i:%m' "$test_home/.zshrc")" = "$copy_metadata" ]] || fail 'Converted copy was rewritten'
if /bin/bash "$repo_dir/install.sh" --unknown >/dev/null 2>&1; then
  printf 'Unknown options must fail\n' >&2; exit 1
fi
printf 'install smoke: PASS\n'
