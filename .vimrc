" Editing and navigation.
set nocompatible
syntax on
filetype plugin indent on
set number relativenumber cursorline showcmd
set ignorecase smartcase incsearch hlsearch
set tabstop=4 shiftwidth=4 softtabstop=4 expandtab
set splitright splitbelow
set wildmenu scrolloff=8

set background=dark
colorscheme desert
if has('clipboard')
  set clipboard=unnamedplus
endif

" Keep backups, swap and undo files out of project directories.
let s:state = (empty($XDG_STATE_HOME) ? expand('~/.local/state') : $XDG_STATE_HOME) . '/vim'
for s:dir in ['backup', 'swap', 'undo']
  call mkdir(s:state . '/' . s:dir, 'p', 0700)
endfor
let &backupdir = s:state . '/backup//'
let &directory = s:state . '/swap//'
set backup
if has('persistent_undo')
  let &undodir = s:state . '/undo//'
  set undofile
endif
unlet s:dir s:state

" Built-in file explorer; no plugin installation required.
nnoremap <silent> <C-n> :Lexplore<CR>
