# Login shells get Homebrew's binaries, manuals and completions.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

typeset -U path PATH
path=("$HOME/.local/bin" $path)
if [[ -n ${HOMEBREW_PREFIX:-} ]]; then
  path=("$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/sbin" $path)
  if [[ -d "$HOMEBREW_PREFIX/opt/python@3.14/libexec/bin" ]]; then
    path=("$HOMEBREW_PREFIX/opt/python@3.14/libexec/bin" $path)
  fi
fi
[[ -n ${VIRTUAL_ENV:-} && -d "$VIRTUAL_ENV/bin" ]] && path=("$VIRTUAL_ENV/bin" $path)
export PATH
