# Настройки macOS

Homebrew устанавливает программы, zsh использует Oh My Zsh, Python-проекты хранят зависимости в своих `.venv`, которыми управляет [uv](https://docs.astral.sh/uv/).

## Установка

```sh
git clone https://github.com/kirillyat/configurations.git
cd configurations
./install.sh
```

Скрипт устанавливает недостающие пакеты из `Brewfile` без обновления уже установленных, добавляет Oh My Zsh и копирует конфиги. Существующие файлы и даже сломанные симлинки сохраняются в отдельный каталог `~/.local/state/configurations/backups/`. Одинаковые файлы при повторном запуске не меняются. Для другого места резервных копий задай `CONFIGURATIONS_BACKUP_ROOT`.

Только подключить конфиги, без установки программ и обращения к сети:

```sh
./install.sh --dotfiles-only
```

Расширения и настройки VS Code применяются флагом `--with-vscode`; без установки Homebrew-пакетов: `./install.sh --dotfiles-only --with-vscode`. После установки открой новую вкладку терминала. Для обновления домашних копий снова запусти `./install.sh --dotfiles-only`. По желанию `--symlink` создаёт ссылки вместо копий; не используй этот режим, если Codex получил write-доступ к отдельным домашним файлам: песочница может отклонять такие writable roots. В режиме `--symlink` не перемещай клон, пока на него ссылаются домашние конфиги.

## Терминал

`.zprofile` подключает Homebrew для login shell. `.zshrc` также работает в обычном interactive shell. В PATH есть `bin`, `sbin`, `~/.local/bin` и Python 3.15; активированная `.venv` имеет приоритет. Повторяющиеся пути удаляются.

Дополнения Homebrew и `zsh-completions` добавляются до единственного `compinit` внутри Oh My Zsh. Затем подключаются autosuggestions, личные настройки и последним syntax-highlighting. `zsh-autocomplete` не используется: у него другая схема инициализации. История сохраняет 50 000 команд. `thefuck` загружается при первом вызове `fuck`, GitHub CLI не вызывается на старте. `termup` вручную обновляет Oh My Zsh и пакеты Homebrew.

Машинные настройки хранятся в `~/.zshrc.local`. Этот файл не входит в репозиторий. Токены и пароли не следует добавлять даже в приватные dotfiles; репозиторий может быть публичным.

В Vim `Ctrl-N` открывает встроенный обозреватель файлов netrw. Сторонний NERDTree для этого не нужен.

## Python

Рабочий Python — Homebrew `python@3.15`. Окружения TwelveAfrica и системный Python сохраняются. Другие minor-версии могут требоваться установленным CLI или существующим проектам: их удаляют только после проверки ссылок `.venv/pyvenv.cfg` и зависимостей Homebrew. Системный Python macOS не меняется.

Конфиг `~/.config/uv/uv.toml` предпочитает интерпретаторы из PATH и запрещает незапрошенные загрузки новых версий. Для проекта, которому явно нужна другая версия, можно выполнить `uv python install 3.13`. Настройки и lock-файлы самого проекта сохраняют приоритет.

Новый проект с фиксированной версией и зависимостями:

```sh
mkdir example && cd example
uv init --python 3.15
uv add requests
uv run python main.py
```

Существующий проект с `pyproject.toml` и `uv.lock`: `uv sync`, затем `uv run ...`. Для проекта с `requirements.txt`:

```sh
uv venv --python 3.15
uv pip install -r requirements.txt
source .venv/bin/activate
python main.py
```

`uv pip` не требует установленного в `.venv` pip. Если программе нужен именно `python -m pip`, создай окружение с `uv venv --seed --python 3.15`.

Отдельные CLI устанавливаются через `uv tool install <tool>`, разовый запуск — `uvx <tool>`. Библиотеки вроде numpy, pandas и torch ставятся в проекты, а не через pipx. Для разового скрипта: `uv run --with pandas script.py`.

Глобальный `pip install` в Homebrew Python блокируется механизмом [externally managed environments](https://docs.brew.sh/Language-Runtimes-and-Packages). Это нормальная защита: не удаляй `EXTERNALLY-MANAGED` и не используй `--break-system-packages`.

## Jupyter

Редактор можно держать в отдельной среде, а ядро — в среде проекта:

```sh
uv tool install --python 3.15 jupyterlab
# Внутри проекта:
uv add --dev ipykernel
uv run python -m ipykernel install --user --name example --display-name 'Python (example)'
jupyter-lab
```

При переименовании или удалении проекта проверь его ядро. Список ядер: `uv tool run --from jupyterlab jupyter kernelspec list`. Рабочие среды и ядра не удаляются при применении этих конфигов.

## VS Code

`./install.sh --dotfiles-only --with-vscode` устанавливает только недостающие расширения из выбранного базового списка и объединяет настройки с существующим User settings. Темы, AI-интеграции, другие языки, комментарии и дополнительные поля сохраняются. Семь устаревших Python-настроек удаляются. Исходный файл сохраняется в резервной папке. Для JSONC используется одна локальная зависимость `jsonc-parser`, закреплённая в `tools/vscode/package-lock.json`; глобальные npm-пакеты не нужны.

Глобальный `python.defaultInterpreterPath` равен `python`: это включает автоматический выбор среды проекта и не подставляет каталог расширения в окне без открытой папки. В проектах расширение предпочитает локальную `.venv`, вне проектов используется рабочий Python 3.15. Для проектов с уже сохранённым выбором интерпретатора один раз выполни **Python: Select Interpreter** и выбери свою `.venv`. В новом встроенном терминале активируется это окружение; используется login zsh с домашними конфигами. Code Runner также запускает выбранный интерпретатор.

Black форматирует Python при сохранении, isort упорядочивает импорты при явном сохранении с профилем Black. Оба используют комплектные версии расширений, без установки в глобальный Python. Настройки `pyproject.toml` конкретного проекта сохраняют приоритет.

В ноутбуке выбирай `.venv` проекта через **Select Kernel**. Если ядро ещё не установлено, добавь `ipykernel` в проект: `uv add --dev ipykernel`. Существующие ядра и сохранённые выборы не переписываются.

`vscode-extensions.txt` содержит базовый набор, а не полный дамп установленного. Другие установленные расширения скрипт не удаляет. В C++ автодополнение обеспечивает clangd, а cpptools остаётся для отладки; второй IntelliSense отключён. Остальные личные предпочтения сохраняются.

## Проверки и обслуживание

```sh
bash -n install.sh check-brewfile.sh tests/install-smoke.sh
zsh -n .zshrc .zprofile
bash tests/install-smoke.sh
npm ci --prefix tools/vscode --ignore-scripts --no-audit --no-fund
node --test tools/vscode/apply-settings.test.cjs
bash tests/vscode-install-smoke.sh
./check-brewfile.sh
brew doctor
brew cleanup --dry-run
brew autoremove --dry-run
```

CI проверяет синтаксис и установку конфигов в изолированном HOME. Свежесть Brewfile проверяется отдельно по расписанию и вручную; приложения на CI не устанавливаются.

Версии программ обновляются вручную через `termup`. Ежедневная фоновая задача, если она настроена, выполняет только `brew update` — обновляет список доступных версий.

Перед уборкой отличай кэш от данных. `uv cache prune` удаляет ненужные записи штатным способом. `brew cleanup` чистит старые загрузки. `.venv`, Python managed installations, pipx/uv tool environments, Docker/Colima volumes и данные PostgreSQL кэшем не являются.

`Brewfile` — список выбранных программ для новой машины. Текущая машина может содержать дополнительные приложения. Не запускай `brew bundle cleanup --force` автоматически. Для сравнения сохрани инвентаризацию отдельно: `brew bundle dump --file=/tmp/Brewfile.inventory --force`.

## Файлы

| Файл | Назначение |
|---|---|
| `Brewfile` | программы для новой машины |
| `install.sh` | установка и безопасная замена конфигов |
| `.zprofile`, `.zshrc` | PATH, completion, история, плагины |
| `.vimrc` | Vim без обязательных сторонних плагинов |
| `config/uv/uv.toml` | правила выбора Python |
| `.gitconfig`, `.gitignore_global` | настройки Git |
| `check-brewfile.sh` | проверка доступности пакетов |
| `tests/install-smoke.sh` | проверка резервных копий и повторной установки |
| `vscode-settings.json`, `vscode-extensions.txt` | настройки VS Code по запросу |
| `vscode-settings.remove.json`, `tools/vscode/` | удаление устаревших ключей и объединение JSONC |
