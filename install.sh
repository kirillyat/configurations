#!/usr/bin/env bash
# Настройка нового мака одной командой: ./install.sh
# Скрипт идемпотентный — можно запускать повторно.
set -euo pipefail

cd "$(dirname "$0")"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }

# --- 1. Homebrew ---
if ! command -v brew &>/dev/null; then
  step "Устанавливаю Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# --- 2. Пакеты и приложения из Brewfile ---
step "Устанавливаю пакеты из Brewfile"
brew bundle --file=Brewfile

# --- 3. Oh My Zsh (нужен для .zshrc) ---
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  step "Устанавливаю Oh My Zsh"
  RUNZSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- 4. Дотфайлы (симлинки, старые файлы сохраняются как *.backup) ---
step "Подключаю дотфайлы"
link_file() {
  local src="$PWD/$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.backup"
    echo "  $dst -> $dst.backup"
  fi
  ln -sf "$src" "$dst"
  echo "  $dst -> $src"
}
link_file .zshrc "$HOME/.zshrc"
link_file .vimrc "$HOME/.vimrc"
link_file .gitconfig "$HOME/.gitconfig"
link_file .gitignore_global "$HOME/.gitignore_global"

# --- 5. VS Code: расширения и настройки ---
if command -v code &>/dev/null; then
  step "Устанавливаю расширения VS Code"
  installed=$(code --list-extensions)
  while read -r ext; do
    [ -z "$ext" ] && continue
    if ! grep -qix "$ext" <<<"$installed"; then
      code --install-extension "$ext"
    fi
  done < vscode-extensions.txt

  step "Копирую настройки VS Code"
  vscode_settings="$HOME/Library/Application Support/Code/User/settings.json"
  mkdir -p "$(dirname "$vscode_settings")"
  if [ -f "$vscode_settings" ] && ! cmp -s vscode-settings.json "$vscode_settings"; then
    cp "$vscode_settings" "$vscode_settings.backup"
  fi
  cp vscode-settings.json "$vscode_settings"
fi

step "Готово!"
echo "Перезапусти терминал (или: source ~/.zshrc)"
