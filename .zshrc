# Добавление путей
export PATH="/usr/local/bin:$PATH"
export PATH=/opt/homebrew/bin:$PATH

# Алиасы
alias ll="ls -la"
alias gs="git status"
eval $(thefuck --alias)

# zsh-autosuggestions
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# zsh-syntax-highlighting
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# zsh-autocomplete (если установлен)
source $(brew --prefix)/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh

# История
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000

# Установите язык (если требуется)
export LANG=en_US.UTF-8
