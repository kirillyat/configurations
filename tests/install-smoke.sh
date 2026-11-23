#!/usr/bin/env bash
# Integration test: existing configs, broken links, repeated installation and backup data.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
test_home="$test_dir/home"
mkdir -p "$test_home/.config/uv"
printf 'original zshrc\n' > "$test_home/.zshrc"
printf 'original uv config\n' > "$test_home/.config/uv/uv.toml"
ln -s /missing/original-vimrc "$test_home/.vimrc"
run_install() {
  env HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
    CONFIGURATIONS_BACKUP_ROOT="$test_dir/backups" \
    /bin/bash "$repo_dir/install.sh" --dotfiles-only
}
run_install
[[ "$(readlink "$test_home/.zshrc")" = "$repo_dir/.zshrc" ]]
[[ "$(readlink "$test_home/.zprofile")" = "$repo_dir/.zprofile" ]]
[[ "$(readlink "$test_home/.config/uv/uv.toml")" = "$repo_dir/config/uv/uv.toml" ]]
backup_count=$(find "$test_dir/backups" -name .zshrc -type f | wc -l | tr -d ' ')
[[ "$backup_count" = 1 ]]
backup_zshrc=$(find "$test_dir/backups" -name .zshrc -type f)
[[ "$(cat "$backup_zshrc")" = 'original zshrc' ]]
backup_vimrc="$(dirname "$backup_zshrc")/.vimrc"
[[ -L "$backup_vimrc" && "$(readlink "$backup_vimrc")" = /missing/original-vimrc ]]
[[ "$(cat "$(dirname "$backup_zshrc")/.config/uv/uv.toml")" = 'original uv config' ]]
run_install
[[ "$(find "$test_dir/backups" -name .zshrc -type f | wc -l | tr -d ' ')" = 1 ]]
if /bin/bash "$repo_dir/install.sh" --unknown >/dev/null 2>&1; then
  printf 'Unknown options must fail\n' >&2; exit 1
fi
printf 'install smoke: PASS\n'
