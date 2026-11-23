# Homebrew also works in interactive shells that are not login shells.
if [[ -z ${HOMEBREW_PREFIX:-} ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

typeset -U path PATH fpath
path=("$HOME/.local/bin" $path)
if [[ -n ${HOMEBREW_PREFIX:-} ]]; then
  path=("$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/sbin" $path)
  if [[ -d "$HOMEBREW_PREFIX/opt/python@3.14/libexec/bin" ]]; then
    path=("$HOMEBREW_PREFIX/opt/python@3.14/libexec/bin" $path)
  fi
  # Completion directories must be present before Oh My Zsh calls compinit.
  for completion_dir in "$HOMEBREW_PREFIX/share/zsh/site-functions" \
                        "$HOMEBREW_PREFIX/opt/zsh-completions/share/zsh-completions"; do
    [[ -d $completion_dir ]] && fpath=("$completion_dir" $fpath)
  done
  unset completion_dir
fi
# Preserve an environment that was activated before starting this shell.
[[ -n ${VIRTUAL_ENV:-} && -d "$VIRTUAL_ENV/bin" ]] && path=("$VIRTUAL_ENV/bin" $path)
export PATH

export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1
export LANG=${LANG:-en_US.UTF-8}

termup() {
  if (( $+functions[omz] )); then
    omz update || return
  fi
  command brew update && command brew upgrade && command brew cleanup
}

# Oh My Zsh owns completion initialization; do not add a second compinit.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME='robbyrussell'
plugins=(git)
zstyle ':omz:update' mode disabled
ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"
mkdir -p "$ZSH_CACHE_DIR"
ZSH_COMPDUMP="$ZSH_CACHE_DIR/zcompdump-$ZSH_VERSION"
if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit
  compinit
  PROMPT='%n@%m %1~ %# '
fi

# Personal aliases override the framework's git plugin aliases.
alias ll='ls -la'
alias ..='cd ..'
alias c='clear'
alias gs='git status'
alias gl='git log --oneline --graph --decorate'
alias gp='git push'
alias gc='git commit -m'
alias gca='git commit --amend'
alias gco='git checkout'
alias gb='git branch'
alias gpl='git pull'

# Apply history preferences after framework defaults.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

# Initialize the correction helper only when it is first requested.
if (( $+commands[thefuck] )); then
  fuck() {
    local initialization
    initialization=$(TF_SHELL=zsh command thefuck --alias) || return
    eval "$initialization"
    fuck "$@"
  }
fi

[[ -r "$HOME/yandex-cloud/path.bash.inc" ]] && source "$HOME/yandex-cloud/path.bash.inc"
[[ -r "$HOME/yandex-cloud/completion.zsh.inc" ]] && source "$HOME/yandex-cloud/completion.zsh.inc"

if [[ -n ${HOMEBREW_PREFIX:-} && -r "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Machine-specific settings stay outside the repository.
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Keep highlighting last so it sees all widgets and key bindings.
if [[ -n ${HOMEBREW_PREFIX:-} && -r "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
