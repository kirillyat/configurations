# Добавление путей
export PATH="/usr/local/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="$PATH:/Users/kirillyat/.local/bin"

# Алиасы
alias update="brew update && brew upgrade && brew cleanup"
alias ll="ls -la"
alias ..="cd .."
alias c="clear"
alias gs="git status"
alias gl="git log --oneline --graph --decorate"
alias gp="git push"
alias gc="git commit -m"
alias gca="git commit --amend"
alias gco="git checkout"
alias gb="git branch"
alias gpl="git pull"
alias python="python3"
eval $(thefuck --alias)

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)

# История
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000

# Установите язык (если требуется)
export LANG=en_US.UTF-8

# Загрузка Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Плагины
# zsh-autosuggestions
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# zsh-syntax-highlighting
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# zsh-autocomplete (если установлен)
source $(brew --prefix)/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh

# Пути для автодополнений
fpath+=/opt/homebrew/opt/zsh-completions/share/zsh-completions

# Инициализация автодополнений
autoload -Uz compinit
compinit