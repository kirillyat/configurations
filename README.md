# Настройка нового мака

Всё ставится одной командой:

```sh
git clone https://github.com/kirillyat/configurations.git && cd configurations
./install.sh
```

Скрипт идемпотентный — его можно безопасно запускать повторно, он доустановит только недостающее.

## Что делает install.sh

1. Устанавливает [Homebrew](https://brew.sh), если его нет
2. Ставит все пакеты и приложения из `Brewfile` (`brew bundle`)
3. Устанавливает [Oh My Zsh](https://ohmyz.sh) (нужен для `.zshrc`)
4. Подключает симлинками дотфайлы — `.zshrc`, `.vimrc`, `.gitconfig`, `.gitignore_global`; старые версии сохраняются как `*.backup`
5. Устанавливает расширения VS Code из `vscode-extensions.txt` и копирует `vscode-settings.json`

## Python

Библиотеки глобально не ставятся — окружения создаются по месту через [uv](https://docs.astral.sh/uv/) (есть в Brewfile):

```sh
# окружение в проекте
uv venv && uv pip install pandas

# разовый скрипт без создания окружения
uv run --with pandas script.py

# jupyter с нужными библиотеками
uv run --with jupyter,pandas,matplotlib jupyter lab
```

## Проверка свежести Brewfile

Пакеты в Homebrew со временем отключают и переименовывают. CI ([check-brewfile.yml](.github/workflows/check-brewfile.yml)) раз в неделю проверяет, что всё из `Brewfile` ещё существует, не deprecated и не переименовано. Локально: `./check-brewfile.sh`.

## Как обновлять списки с текущей машины

```sh
# Пакеты и приложения Homebrew
brew bundle dump --force

# Расширения VS Code
code --list-extensions > vscode-extensions.txt

# Настройки VS Code
cp "$HOME/Library/Application Support/Code/User/settings.json" vscode-settings.json
```

## Файлы

| Файл | Назначение |
|---|---|
| `Brewfile` | пакеты и приложения Homebrew |
| `install.sh` | главный скрипт установки |
| `check-brewfile.sh` | проверка, что пакеты из Brewfile ещё живы |
| `vscode-extensions.txt` | расширения VS Code |
| `vscode-settings.json` | настройки VS Code |
| `.zshrc`, `.vimrc` | конфиги шелла и vim |
| `.gitconfig`, `.gitignore_global` | глобальные настройки git |
