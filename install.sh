#!/usr/bin/env bash
# macOS setup. --dotfiles-only never installs or updates software.
set -euo pipefail
cd "$(dirname "$0")"
repo_dir="$PWD"
dotfiles_only=false
with_vscode=false
use_symlinks=false
for arg in "$@"; do
  case "$arg" in
    --dotfiles-only) dotfiles_only=true ;;
    --with-vscode) with_vscode=true ;;
    --symlink) use_symlinks=true ;;
    --help|-h)
      printf '%s\n' 'Usage: ./install.sh [--dotfiles-only] [--with-vscode] [--symlink]' \
        'Existing files and symlinks are backed up before replacement.'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done
step() { printf '\n==> %s\n' "$1"; }
backup_dir=''
backup_file() {
  local dst="$1" relative
  if [[ -z "$backup_dir" ]]; then
    local backup_root="${CONFIGURATIONS_BACKUP_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/configurations/backups}"
    mkdir -p "$backup_root"
    backup_dir=$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S).XXXXXX")
    chmod 700 "$backup_dir"
  fi
  relative="${dst#"$HOME"/}"
  mkdir -p "$backup_dir/$(dirname "$relative")"
  mv "$dst" "$backup_dir/$relative"
  printf '  backup: %s\n' "$backup_dir/$relative"
}
link_file() {
  local src="$repo_dir/$1" dst="$2"
  if "$use_symlinks"; then
    if [[ -L "$dst" && "$(readlink "$dst")" = "$src" ]]; then return; fi
  elif [[ -f "$dst" && ! -L "$dst" ]] && cmp -s "$src" "$dst"; then
    return
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" || -L "$dst" ]]; then backup_file "$dst"; fi
  if "$use_symlinks"; then
    ln -s "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
  printf '  %s <- %s\n' "$dst" "$src"
}
if ! "$dotfiles_only"; then
  if ! command -v brew >/dev/null 2>&1; then
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [[ -x "$brew_bin" ]]; then eval "$("$brew_bin" shellenv)"; break; fi
    done
  fi
  if ! command -v brew >/dev/null 2>&1; then
    step 'Install Homebrew'
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    case "$(uname -m)" in
      arm64) eval "$(/opt/homebrew/bin/brew shellenv)" ;;
      *) eval "$(/usr/local/bin/brew shellenv)" ;;
    esac
  fi
  step 'Install missing Brewfile packages'
  brew bundle --no-upgrade --file="$repo_dir/Brewfile"
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    step 'Install Oh My Zsh'
    RUNZSH=no KEEP_ZSHRC=yes CHSH=no \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi
fi
step 'Install dotfiles'
link_file .zprofile "$HOME/.zprofile"
link_file .zshrc "$HOME/.zshrc"
link_file .vimrc "$HOME/.vimrc"
link_file .gitconfig "$HOME/.gitconfig"
link_file .gitignore_global "$HOME/.gitignore_global"
link_file config/uv/uv.toml "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml"
if "$with_vscode"; then
  if ! command -v code >/dev/null 2>&1; then
    printf 'VS Code CLI is unavailable; skipping VS Code settings.\n' >&2
  else
    for tool in node npm; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'VS Code settings merge requires %s (included in Brewfile).\n' "$tool" >&2
        exit 1
      fi
    done
    if ! node -e 'try { process.exit(require(process.argv[1]).version === "3.3.1" ? 0 : 1); } catch { process.exit(1); }' \
        "$repo_dir/tools/vscode/node_modules/jsonc-parser/package.json"; then
      npm ci --prefix "$repo_dir/tools/vscode" --ignore-scripts --no-audit --no-fund
    fi
    dst="$HOME/Library/Application Support/Code/User/settings.json"
    vscode_candidate=$(mktemp)
    trap 'rm -f "$vscode_candidate"' EXIT
    # Parse and validate the merge before backing up or changing existing settings.
    node "$repo_dir/tools/vscode/apply-settings.cjs" "$dst" \
      "$repo_dir/vscode-settings.json" "$repo_dir/vscode-settings.remove.json" > "$vscode_candidate"

    step 'Install missing VS Code extensions'
    installed=$(code --list-extensions)
    while IFS= read -r ext || [[ -n "$ext" ]]; do
      [[ -z "$ext" || "$ext" = \#* ]] && continue
      if ! grep -Fqix -- "$ext" <<<"$installed"; then code --install-extension "$ext"; fi
    done < vscode-extensions.txt

    # Settings Sync or the editor may have changed User settings while extensions
    # were being installed. Merge the latest file instead of the preflight copy.
    node "$repo_dir/tools/vscode/apply-settings.cjs" "$dst" \
      "$repo_dir/vscode-settings.json" "$repo_dir/vscode-settings.remove.json" > "$vscode_candidate"
    step 'Merge VS Code settings'
    if ! cmp -s "$vscode_candidate" "$dst"; then
      mkdir -p "$(dirname "$dst")"
      if [[ -e "$dst" || -L "$dst" ]]; then backup_file "$dst"; fi
      cp "$vscode_candidate" "$dst"
    fi
  fi
fi
step 'Done; open a new terminal tab'
if [[ -n "$backup_dir" ]]; then printf 'Backups: %s\n' "$backup_dir"; fi
