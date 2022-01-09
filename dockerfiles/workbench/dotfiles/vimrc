if has('vim_starting')
	set nocompatible
	if !isdirectory(expand("~/.vim/bundle/neobundle.vim/"))
		echo "install neobundle..."
		:call system("git clone https://github.com/Shougo/neobundle.vim ~/.vim/bundle/neobundle.vim")
	endif
	set runtimepath+=~/.vim/bundle/neobundle.vim/
endif
call neobundle#begin(expand('~/.vim/bundle'))
let g:neobundle_default_git_protocol='https'

NeoBundleFetch 'Shougo/neobundle.vim'
NeoBundle 'nanotech/jellybeans.vim'
NeoBundleCheck
NeoBundle 'scrooloose/nerdtree'
NeoBundle 'nathanaelkane/vim-indent-guides'
NeoBundle 'bronson/vim-trailing-whitespace'
NeoBundle 'mmai/vim-markdown-wiki'
call neobundle#end()

filetype plugin indent on
set t_Co=256
syntax on

set cursorline
set backupskip=/tmp/*,/private/tmp/*
set number
set syntax=markdown
set foldmethod=marker
set cursorcolumn
"set expandtab
set tabstop=4
set shiftwidth=4
set list
set listchars=tab:»-,trail:-,eol:↲,extends:»,precedes:«,nbsp:%

au BufRead,BufNewFile *.md set filetype=markdown
noremap <C-a> ^
noremap <C-e> $
nnoremap <silent><C-e> :NERDTreeToggle<CR>
nnoremap <BS> :MdwiReturn<CR>
let g:indent_guides_enable_on_vim_startup = 1
"colorscheme blue
colorscheme murphy
colorscheme industry

function! ZenkakuSpace()
	highlight ZenkakuSpace cterm=underline ctermfg=lightblue guibg=darkgray
endfunction
if has('syntax')
	augroup ZenkakuSpace
	autocmd!
	autocmd ColorScheme * call ZenkakuSpace()
	autocmd VimEnter,WinEnter,BufRead * let w:m1=matchadd('ZenkakuSpace', '　')
	augroup END
	call ZenkakuSpace()
endif
if &term !~ "xterm-color"
	autocmd BufEnter * if bufname("") !~ "^?[A-Za-z0-9?]*://" | silent! exe '!echo -n "^[k[`basename %`]^[??"' | endif
	autocmd VimLeave * silent! exe '!echo -n "^[k`dirs`^[??"'
endif
:let g:vimwiki_list = [{'path':'~/git/', 'index':'links.wiki'}]

function s:MkNonExDir(file, buf)
    if empty(getbufvar(a:buf, '&buftype')) && a:file!~#'\v^\w+\:\/'
        let dir=fnamemodify(a:file, ':h')
        if !isdirectory(dir)
            call mkdir(dir, 'p')
        endif
    endif
endfunction
augroup BWCCreateDir
    autocmd!
    autocmd BufWritePre * :call s:MkNonExDir(expand('<afile>'), +expand('<abuf>'))
augroup END

execute "set colorcolumn=" . join(range(81, 9999), ',')
hi ColorColumn ctermbg=90 guibg=#2f4f4f
