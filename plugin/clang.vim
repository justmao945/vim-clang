"{{{ Description
" Script Name: clang.vim
" Version:     1.0.0-beta (2013-xx-xx)
" Authors:     2013~     Jianjun Mao <justmao945@gmail.com>
"
" Description: Use of clang to parse in C/C++ source files.
"
" Options:
"  - g:clang_auto
"       If equals to 1, automatically complete after ->, ., ::
"       Default: 1
"
"  - g:clang_c_options
"       Option added at the end of clang command for C sources.
"       Default: ''
"
"  - g:clang_cpp_options
"       Option added at the end of clang command for C++ sources.
"       Default: ''
"       Note: Add "-std=c++11" to support C++0x features
"             Add "-stdlib=libc++" to use libcxx
"
"  - g:clang_dotfile
"       Each project can have a dot file at his root, containing the compiler
"       options. This is useful if you're using some non-standard include paths.
"       Default: '.clang'
"       Note: Relative include and library path is recommended.
"
"  - g:clang_exec
"       Name or path of executable clang.
"       Default: 'clang'
"       Note: Use this if clang has a non-standard name, or isn't in the path.
"   
"  - g:clang_vim_exec
"       Name or path of executable vim.
"       Default: 'vim'
"       Note: This is option is used in async mode to startup a new vim
"       process. Please add vim to your system PATH or overwrite this var.
"       Please note that default the command 'vim' will not act as a server,
"       instead you must add '--servername XX' to start a unique server.
"
"  - g:clang_pwheight
"       Maximum height of completion preview window if has it.
"       Default: 4
"
"  - g:clang_diagsopt
"       This option is a string combined with split mode, colon, and max height
"       of split window. Colon and max height are optional.
"       e.g.
"         let g:clang_diagsopt = 'b:rightbelow:6'
"         let g:clang_diagsopt = 'b:rightbelow'
"         let g:clang_diagsopt = ''   " <- this disable diagnostics
"       If it equals '', disable clang diagnostics after completion, otherwise
"       diagnostics will be put in a split window/viewport.
"       Split policy indicators and their corresponding modes are:
"       ''            :disable diagnostics window
"       't:topleft'   :split SCREEN horizontally, with new split on the top
"       't:botright'  :split SCREEN horizontally, with new split on the bottom
"       'b:rightbelow':split VIEWPORT horizontally, with new split on the bottom
"       'b:leftabove' :split VIEWPORT horizontally, with new split on the top
"       Default: 'b:rightbelow:6'
"       Note: Split modes are indicated by a single letter. Upper-case letters
"             indicate that the SCREEN (i.e., the entire application "window" 
"             from the operating system's perspective) should be split, while
"             lower-case letters indicate that the VIEWPORT (i.e., the "window"
"             in Vim's terminology, referring to the various subpanels or 
"             splits within Vim) should be split.
"
"  - g:clang_statusline
"       Status line showed in preview window and diagnostics window.
"       The first %s is the place to hold messages generated from clang.
"       Default: '%s\ \|\ %%l/\%%L\ \|\ %%p%%%%'
"                Something like   "1 error generated. | 1/5 | 20%"
"
"  - g:clang_stdafx_h
"       Clang default header file name to generate PCH. Clang will find the
"       stdafx header to speed up completion.
"       Default: stdafx.h
"       Note: Only find this file in clang root and its sub directory "include".
"             If it is not in mentioned dirs, it must be defined in the dotclang
"             file "-include-pch /path/to/stdafx.h.pch".
"             Additionally, only find PCH file stdafx for C++, but not for C.
"
" Commands:
"  - ClangGenPCHFromFile <stdafx.h>
"       Generate PCH file from the give file name <stdafx.h>, which can be %
"       (aka current file name).
"
"  - ClangClosePreviewDiagWindow
"       Close preview and diagnostics window for current buffer.
"       Or uses a leader map to do this this
"         map <silent> <Leader>c <Esc>:ClangClosePreviewDiagWindow<CR>
" Notes:
"   1. Make sure `clang` is available in path when g:clang_exec is empty
"
"   2. Make sure `vim` is available in path if uses asynchronized mode(default)
"     if g:clang_vim_exec is empty.
"
"   3. Set completeopt+=preview to show prototype in preview window.
"      But there's no local completeopt, so we use BufEnter event.
"      e.g. only for C++ sources but not for C, add
"         au BufEnter *.cc,*.cpp,*.hh,*hpp set completeopt+=preview
"         au BufEnter *.c,*.h set completeopt-=preview
"      to .vimrc
"
" TODO:
"   1. Private members filter
"   2. Remove OmniComplete .... Pattern Not Found error?...
"      * This has been fixed in asynchronized mode, because I can control the
"        completion action.
"   3. Test cases....
"      * Really hard to do this automatically, just test manually.
"
" Issues:
"   1. When complete an identifier only has a char, the char will be deleted by
"      OmniCompletion with 'longest' completeopt.
"      Vim verison: 7.3.754
"   
" References:
"   [1] http://clang.llvm.org/docs/
"   [2] VIM help file
"   [3] VIM scripts [vim-buffergator, clang_complete, AsyncCommand,
"                    vim-marching]
"}}}
"{{{ Global initialization
if exists('g:clang_loaded')
  finish
endif
let g:clang_loaded = 1

if !exists('g:clang_auto')
  let g:clang_auto = 1
endif

if !exists('g:clang_c_options')
  let g:clang_c_options = ''
endif

if !exists('g:clang_cpp_options')
  let g:clang_cpp_options = ''
endif

if !exists('g:clang_dotfile')
  let g:clang_dotfile = '.clang'
endif

if !exists('g:clang_exec')
  let g:clang_exec = 'clang'
endif

if !exists('g:clang_vim_exec')
  let g:clang_vim_exec = 'vim'
endif

if !exists('g:clang_pwheight')
  let g:clang_pwheight = 4
endif

if !exists('g:clang_diagsopt')
  let g:clang_diagsopt = 'b:rightbelow:6'
endif

if !exists('g:clang_statusline')
  let g:clang_statusline='%s\ \|\ %%l/\%%L\ \|\ %%p%%%%'
endif

if !exists('g:clang_stdafx_h')
  let g:clang_stdafx_h = 'stdafx.h'
endif

" Init on c/c++ files
au FileType c,cpp call <SID>ClangCompleteInit()
"}}}
" {{{ s:Complete[Dot|Arrow|Colon]
" Tigger a:cmd when cursor is after . -> and ::

func! s:ShouldComplete()
  if getline('.') =~ '#\s*\(include\|import\)' || getline('.')[col('.') - 2] == "'"
    return 0
  endif
  if col('.') == 1
    return 1
  endif
  for id in synstack(line('.'), col('.') - 1)
    if synIDattr(id, 'name') =~ 'Comment\|String\|Number\|Char\|Label\|Special'
      return 0
    endif
  endfor
  return 1
endf

func! s:CompleteDot()
  if s:ShouldComplete()
    return ".\<C-x>\<C-o>"
  endif
  return '.'
endf

func! s:CompleteArrow()
  if s:ShouldComplete() && getline('.')[col('.') - 2] == '-'
    return ">\<C-x>\<C-o>"
  endif
  return '>'
endf

func! s:CompleteColon()
  if s:ShouldComplete() && getline('.')[col('.') - 2] == ':'
    return ":\<C-x>\<C-o>"
  endif
  return ':'
endf
"}}}
"{{{ s:DiscoverIncludeDirs
" Discover clang default include directories.
" Output of `echo | clang -c -v -x c++ -`:
"   clang version ...
"   Target: ...
"   Thread model: ...
"    "/usr/bin/clang" -cc1 ....
"   clang -cc1 version ...
"   ignoring ..
"   #include "..."...
"   #include <...>...
"    /usr/include/..
"    /usr/include/
"    ....
"   End of search list.
"
" @clang Path of clang.
" @options Additional options passed to clang, e.g. -stdlib=libc++
" @return List of dirs: ['path1', 'path2', ...]
func! s:DiscoverIncludeDirs(clang, options)
  let l:command = printf('echo | %s -fsyntax-only -v %s -', a:clang, a:options)
  let l:clang_output = split(system(l:command), "\n")
  
  let l:i = 0
  for l:line in l:clang_output
    if l:line =~# '^#include'
      break
    endif
    let l:i += 1
  endfor
  
  let l:clang_output = l:clang_output[l:i+1 : -1]
  let l:res = []
  for l:line in l:clang_output
    if l:line[0] == ' '
      call add(l:res, fnameescape(l:line[1:-1]))
    elseif l:line =~# '^End'
      break
    endif
  endfor
  return l:res
endf
"}}}
"{{{  s:GenPCH
" Generate clang precompiled header.
" A new file with postfix '.pch' will be created if success.
" Note: There's no need to generate PCH files for C headers, as they can be
" parsed very fast! So only big C++ headers are recommended to be pre-compiled.
"
" @clang   Path of clang
" @options Additional options passed to clang.
" @header  Path of header to generate
" @return  Output of clang
"
func! s:GenPCH(clang, options, header)
  let l:header = fnameescape(expand(a:header))
  if l:header !~? '.h'
    let cho = confirm('Not a C/C++ header: ' . l:header . "\n" .
          \ 'Continue to generate PCH file ?',
          \ "&Yes\n&No", 2)
    if cho != 1 | return | endif
  endif
  
  let l:command = printf('%s -cc1 %s -emit-pch -o %s.pch %s', a:clang, a:options, l:header, l:header)
  let l:clang_output = system(l:command)

  if v:shell_error
    echoe 'Clang returns error ' . v:shell_error
    echoe l:command
    echoe l:clang_output
  else
    echoe 'Clang creates PCH flie ' . l:header . '.pch successfully!'
  endif
  return l:clang_output
endf
"}}}
" {{{ s:HasPreviewAbove
" 
" Detect above view is preview window or not.
"
func! s:HasPreviewAbove()
  let l:cbuf = bufnr('%')
  let l:has = 0
  wincmd k  " goto above
  if &previewwindow
    let l:has = 1
  endif
  exe bufwinnr(l:cbuf) . 'wincmd w'
  return l:has
endf
"}}}
" {{{ s:ParseCompletePoint
" <IDENT> indicates an identifier
" </> the completion point
" <.> including a `.` or `->` or `::`
" <s> zero or more spaces and tabs
" <*> is anything other then the new line `\n`
"
" 1  <*><IDENT><s></>         complete identfiers start with <IDENT>
" 2  <*><.><s></>             complete all members
" 3  <*><.><s><IDENT><s></>   complete identifers start with <IDENT>
" @return [start, base] start is used by omni and base is used to filter
" completion result
func! s:ParseCompletePoint()
    let l:line = getline('.')
    let l:start = col('.') - 1 " start column
    
    "trim right spaces
    while l:start > 0 && l:line[l:start - 1] =~ '\s'
      let l:start -= 1
    endwhile
    
    let l:col = l:start
    while l:col > 0 && l:line[l:col - 1] =~# '[_0-9a-zA-Z]'  " find valid ident
      let l:col -= 1
    endwhile
    
    let l:base = ''  " end of base word to filter completions
    if l:col < l:start " may exist <IDENT>
      if l:line[l:col] =~# '[_a-zA-Z]' "<ident> doesn't start with a number
        let l:base = l:line[l:col : l:start-1]
        let l:start = l:col " reset l:start in case 1
      else
        echoe 'Can not complete after an invalid identifier <'
            \. l:line[l:col : l:start-1] . '>'
        return [-3, l:base]
      endif
    endif
    
    " trim right spaces
    while l:col > 0 && l:line[l:col -1] =~ '\s'
      let l:col -= 1
    endwhile
   
    let l:ismber = 0
    if (l:col >= 1 && l:line[l:col - 1] == '.')
        \ || (l:col >= 2 && l:line[l:col - 1] == '>' && l:line[l:col - 2] == '-')
        \ || (l:col >= 2 && l:line[l:col - 1] == ':' && l:line[l:col - 2] == ':' && &filetype == 'cpp')
      let l:start  = l:col
      let l:ismber = 1
    endif
    
    "Noting to complete, pattern completion is not supported...
    if ! l:ismber && empty(l:base)
      return [-3, l:base]
    endif
    " echom printf("start: %s, base: %s", l:start, l:base)
    return [l:start, l:base]
endf
" }}}
" {{{  s:ParseCompletionResult
" Completion output of clang:
"   COMPLETION: <ident> : <prototype>
"   0           12     c  c+3
" @output Raw clang completion output
" @base   Base word of completion
" @return Parsed result list
func! s:ParseCompletionResult(output, base)
  let l:res = []
  let l:has_preview = &completeopt =~# 'preview'
  for l:line in a:output
    let l:s = stridx(l:line, ':', 13)
    if l:s == -1
      let l:word  = l:line[12:-1]
      let l:proto = l:word
    else
      let l:word  = l:line[12 : l:s-2]
      let l:proto = l:line[l:s+2 : -1]
    endif
    
    if l:word !~# '^' . a:base || l:word =~# '(Hidden)$'
      continue
    endif
    
    let l:proto = substitute(l:proto, '\(<#\)\|\(#>\)\|#', '', 'g')
    if empty(l:res) || l:res[-1]['word'] !=# l:word
      call add(l:res, {
          \ 'word': l:word,
          \ 'menu': l:has_preview ? '' : l:proto,
          \ 'info': l:proto,
          \ 'dup' : 1 })
    elseif !empty(l:res) " overload functions, for C++
      let l:res[-1]['info'] .= "\n" . l:proto
    endif
  endfor

  if l:has_preview && ! s:HasPreviewAbove()
    pclose " close preview window before completion
  endif
  
  return l:res
endf
" }}}
" {{{ s:DeleteAfterReadTmps
" @tmps Tmp files name list
" @return a list of read files
func! s:DeleteAfterReadTmps(tmps)
  if type(a:tmps) != type([])
    echoe "Invalid arg ". a:tmps
  endif
  let l:res = []
  let l:i = 0
  while l:i < len(a:tmps)
    call add(l:res, readfile(a:tmps[ l:i ]))
    call delete(a:tmps[ l:i ])
    let l:i = l:i + 1
  endwhile
  return l:res
endf
"}}}
"{{{ s:ShowDiagnostics
" Split a window to show clang diagnostics. If there's no diagnostics, close
" the split window.
"
" @diags A list of lines from clang diagnostics, or a diagnostics file name.
" @mode  Split policy indicators and their corresponding modes are:
"       't:topleft'   :split SCREEN horizontally, with new split on the top
"       't:botright'  :split SCREEN horizontally, with new split on the bottom
"       'b:rightbelow':split VIEWPORT horizontally, with new split on the bottom
"       'b:leftabove' :split VIEWPORT horizontally, with new split on the top
" @maxheight Maximum window height.
" @statusline Status line format
" @return -1 or window number
func! s:ShowDiagnostics(diags, mode, maxheight, statusline)
  let l:diags = a:diags
  if type(l:diags) == type('') " diagnostics file name
    let l:diags = readfile(l:diags)
  elseif type(l:diags) != type([])
    echoe 'Invalid arg ' . l:diags
    return -1
  endif
  
  " according to mode, create t: or b: var
  let l:p = a:mode[0]
  if !exists(l:p.':clang_diags_bufnr') || !bufexists(eval(l:p.':clang_diags_bufnr'))
    exe "let ".l:p.":clang_diags_bufnr = bufnr('ClangDiagnostics@" .
          \ last_buffer_nr() . "', 1)"
  endif
  let l:diags_bufnr = eval(l:p.':clang_diags_bufnr')
  let l:sp = a:mode[2:-1]
  let l:cbuf = bufnr('%')

  let l:diags_winnr = bufwinnr(l:diags_bufnr)
  if l:diags_winnr == -1
    if !empty(l:diags)  " split a new window
      exe 'silent keepalt keepjumps keepmarks ' .l:sp. ' sbuffer ' .l:diags_bufnr
    else
      return -1
    endif
  else " goto diag window  no matter diagnostics is empty or not
    exe l:diags_winnr . 'wincmd w'
    if empty(l:diags) " hide the diag window then restore cursor and !!RETURN!!
      hide
      " back to current window
      exe bufwinnr(l:cbuf) . 'wincmd w'
      return l:diags_winnr
    endif
  endif

  let l:height = len(l:diags) - 1
  if a:maxheight < l:height
    let l:height = a:maxheight
  endif

  " the last line will be showed in status line as file name
  exe 'silent resize '. l:height

  setl modifiable
  silent 1,$ delete _   " clear buffer before write
  
  for l:line in l:diags
    call append(line('$')-1, l:line)
  endfor

  silent 1 " goto the 1st line
    
  setl buftype=nofile bufhidden=hide
  setl noswapfile nobuflisted nowrap nonumber nospell nomodifiable
  setl cursorline
  setl colorcolumn=-1
  
  syn match ClangSynDiagsError    display 'error:'
  syn match ClangSynDiagsWarning  display 'warning:'
  syn match ClangSynDiagsNote     display 'note:'
  syn match ClangSynDiagsPosition display '^\s*[~^ ]\+$'
  
  hi ClangSynDiagsError           guifg=Red     ctermfg=9
  hi ClangSynDiagsWarning         guifg=Magenta ctermfg=13
  hi ClangSynDiagsNote            guifg=Gray    ctermfg=8
  hi ClangSynDiagsPosition        guifg=Green   ctermfg=10

  " change file name to the last line of diags and goto line 1
  exe printf('setl statusline='.a:statusline, escape(l:diags[-1], ' \'))

  " back to current window
  exe bufwinnr(l:cbuf) . 'wincmd w'
  return bufwinnr(l:diags_bufnr)
endf
"}}}
"{{{  s:ShowDiagnosticsAndClear
" This function will do clear diagnostics after calling ShowDiagnostics.
" This is required because if I do quit the diagnostics window, what I 
" want is to ignore this errors, so we should clear all diagnostics
"
" Buffer varialbe
"   b:clang_diags_winnr   <= save
func! s:ShowDiagnosticsAndClear(diags, mode, maxheight, statusline)
  let b:clang_diags_winnr = s:ShowDiagnostics(a:diags, a:mode, a:maxheight, a:statusline)
  if ! empty(a:diags)
    call remove(a:diags, 0, -1)
  endif
endf
"}}}
"{{{ s:CloseDiagnosticsWindow
" Close diagnostics and preview window
"
" Buffer varialbe
"   b:clang_diags_winnr   <= use
func! s:CloseDiagnosticsWindow()
  if exists('b:clang_diags_winnr') && b:clang_diags_winnr != -1
    let l:cwn = bufwinnr(bufnr('%'))
    exe b:clang_diags_winnr . 'wincmd w'
    hide
    exe l:cwn . 'wincmd w'
  endif
  pclose
endf
"}}}
"{{{ s:ShrinkPrevieWindow
" Shrink preview window to fit lines.
" Assume cursor is in the editing window, and preview window is above of it.
" @statusline Status line format
func! s:ShrinkPrevieWindow(statusline)
  if &completeopt !~# 'preview'
    return
  endif

  "current view
  let l:cbuf = bufnr('%')
  let l:cft  = &filetype

  wincmd k " go to above view
  if( &previewwindow )
    exe 'resize ' . min([(line('$') - 1), g:clang_pwheight])
    if l:cft !=# &filetype
      exe 'set filetype=' . l:cft
      setl nobuflisted
      exe printf('setl statusline='.a:statusline, 'Prototypes')
    endif
  endif

  " back to current window
  exe bufwinnr(l:cbuf) . 'wincmd w'
endf
"}}}
"{{{ s:ClangCompleteInit
" Initialization for every C/C++ source buffer:
"   1. find set root to file .clang
"   2. read config file .clang
"   3. append user options first
"   3.5 append clang default include directories to option
"   4. setup buffer maps to auto completion
"  
"  Usable vars after return:
"     b:clang_diags => diagnostics created by clang
"     s:clang_diags_mode => updated mode used by ShowDiagnosticsAndClear
"     s:clang_diags_height => update max height of diagnostics window
"     b:clang_isCompleteDone_0/1  => used when CompleteDone event not available
"     b:clang_options => parepared clang cmd options
"     b:clang_options_noPCH  => same as b:clang_options except no pch options
"     b:clang_root => project root to run clang
func! s:ClangCompleteInit()
  let l:cwd = fnameescape(getcwd())
  let l:fwd = fnameescape(expand('%:p:h'))
  exe 'lcd ' . l:fwd
  let l:dotclang = findfile(g:clang_dotfile, '.;')

  " Firstly, add clang options for current buffer file
  let b:clang_options = ''

  " clang root(aka .clang located directory) for current buffer
  if filereadable(l:dotclang)
    let b:clang_root = fnameescape(fnamemodify(l:dotclang, ':p:h'))
    let l:opts = readfile(l:dotclang)
    for l:opt in l:opts
      let b:clang_options .= ' ' . l:opt
    endfor
  else " or means source file directory
    let b:clang_root = l:fwd
  endif
  exe 'lcd '.l:cwd

  " Secondly, add options defined by user
  if &filetype == 'c'
    let b:clang_options .= ' -x c ' . g:clang_c_options
  elseif &filetype == 'cpp'
    let b:clang_options .= ' -x c++ ' . g:clang_cpp_options
  endif
  
  " add include directories
  let l:incs = s:DiscoverIncludeDirs(g:clang_exec, b:clang_options)
  for l:dir in l:incs
    let b:clang_options .= ' -I' . l:dir
  endfor
  
  " backup options without PCH support
  let b:clang_options_noPCH = b:clang_options

  " Create GenPCH command
  com! -nargs=* ClangGenPCHFromFile
        \ call <SID>GenPCH(g:clang_exec, b:clang_options_noPCH, <f-args>)
  
  com! ClangClosePreviewDiagWindow
        \ call <SID>CloseDiagnosticsWindow()

  " try to find PCH files in clang_root and clang_root/include
  " Or add `-include-pch /path/to/x.h.pch` into the root file .clang manully
  if &filetype ==# 'cpp' && b:clang_options !~# '-include-pch'
    let l:cwd = fnameescape(getcwd())
    exe 'lcd ' . b:clang_root
    let l:afx = findfile(g:clang_stdafx_h, '.;./include') . '.pch'
    if filereadable(l:afx)
      let b:clang_options .= ' -include-pch ' . fnameescape(l:afx)
    endif
    exe 'lcd '.l:cwd
  endif

  setl completefunc=ClangComplete
  setl omnifunc=ClangComplete

  if g:clang_auto   " Auto completion
    inoremap <expr> <buffer> . <SID>CompleteDot()
    inoremap <expr> <buffer> > <SID>CompleteArrow()
    if &filetype == 'cpp'
      inoremap <expr> <buffer> : <SID>CompleteColon()
    endif
  endif

  " CompleteDone event is available since version 7.3.598
  if exists("##CompleteDone")
    " Automatically resize preview window after completion.
    " Default assume preview window is above of the editing window.
    au CompleteDone <buffer> call <SID>ShrinkPrevieWindow(g:clang_statusline)
  else
    let b:clang_isCompleteDone_0 = 0
    au CursorMovedI <buffer>
          \ if b:clang_isCompleteDone_0 |
          \   call <SID>ShrinkPrevieWindow(g:clang_statusline) |
          \   let b:clang_isCompleteDone_0 = 0 |
          \ endif
  endif

  " Window is shared by buffers in the same tabpage,
  " and viewport is private for every source buffer.
  " Note: b:clang_diags is created in ClangComplete(...)
  if g:clang_diagsopt =~# '^[bt]:[a-z]\+\(:[0-9]\+\)\?$'
    let l:i = stridx(g:clang_diagsopt, ':', 2)
    let s:clang_diags_mode   = g:clang_diagsopt[0 : l:i-1]
    let s:clang_diags_height = g:clang_diagsopt[l:i+1 : -1]
    let b:clang_diags = [] " init empty diags
    if exists("##CompleteDone")
      " Automatically show clang diagnostics after completion.
      au CompleteDone <buffer> 
            \ call <SID>ShowDiagnosticsAndClear(b:clang_diags,
            \ s:clang_diags_mode, s:clang_diags_height, g:clang_statusline)
    else
      " FIXME I don't know why VIM escapes after press a key when the
      " completion pattern not found...
      let b:clang_isCompleteDone_1 = 0
      au CursorMovedI <buffer>
            \ if b:clang_isCompleteDone_1 |
            \   call <SID>ShowDiagnosticsAndClear(b:clang_diags,
                \   s:clang_diags_mode, s:clang_diags_height, g:clang_statusline) |
            \   let b:clang_isCompleteDone_1 = 0 |
            \ endif
    endif
  endif
endf
"}}}
"{{{ s:ExecuteClang
" Execute clang binary to generate completions and diagnostics.
" Buffer vars:
"     b:clang_state => {
"       'state' :  // updated to 'ready' in sync mode
"       'stdout':  // updated in sync mode
"       'stderr':  // updated in sync mode
"     }
" @root Clang root, project directory
" @clang_exe Executable clang binary image
" @clang_options Options appended to clang binary image
" @line Line to complete
" @col Column to complete
" @vim_exe Executable vim binary image, used in async mode
" @return [completion, diagnostics]
func! s:ExecuteClang(root, clang_exe, clang_options, line, col, vim_exe)
  let l:cwd = fnameescape(getcwd())
  exe 'lcd ' . a:root
  let l:src = fnameescape(expand('%:p:.'))  " Thanks RageCooky, fix when a path has spaces.
  let l:command = printf('%s -cc1 -fsyntax-only -code-completion-macros -code-completion-at=%s:%d:%d %s %s',
                      \ a:clang_exe, l:src, a:line, a:col, a:clang_options, l:src)
  " Redir clang diagnostics into a tempfile.
  " * Fix stdout/stderr buffer flush bug? of clang, that COMPLETIONs are not
  "   flushed line by line when not output to a terminal.
  " * FIXME: clang on Win32 will not redirect errors to stderr?
  let l:tmps = [tempname(), tempname()] " FIXME: potential bug for tempname
  let l:command .= ' 1>'.l:tmps[0].' 2>'.l:tmps[1]
  let l:res = [[], []]
  if !exists('v:servername') || empty(v:servername)
    let b:clang_state['state'] = 'ready'
    call system(l:command)
    let l:res = s:DeleteAfterReadTmps(l:tmps)
  else
    let l:keys = printf('<Esc>:call ExecuteClangDone(\"%s\",\"%s\")<Enter>', l:tmps[0], l:tmps[1])
    let l:vcmd = printf('%s -s --noplugin --servername %s --remote-send "%s"', a:vim_exe, v:servername, l:keys)
    let l:command = '('.l:command.';'.l:vcmd.') &'
    call system(l:command)
  endif
  exe 'lcd ' . l:cwd
  let b:clang_state['stdout'] = l:res[0]
  let b:clang_state['stderr'] = l:res[1]
  return l:res
endf
"}}}
" {{{ ExecuteClangDone
" Buffer vars:
"     b:clang_state => {
"       'state' :  // updated to 'sync' in async mode
"       'stdout':  // updated in async mode
"       'stderr':  // updated in async mode
"     }
"     b:clang_diags <= use which created in ClangComplete
"
" Script vars:
"   s:clang_diags_mode
"   s:clang_diags_height
"
" FIXME: global var:
"   g:clang_statusline
func! ExecuteClangDone(tmp1, tmp2)
  let l:res = s:DeleteAfterReadTmps([a:tmp1, a:tmp2])
  let b:clang_state['state'] = 'sync'
  let b:clang_state['stdout'] = l:res[0]
  let b:clang_state['stderr'] = l:res[1]
  call feedkeys("\<Esc>a")
  if ! empty(l:res[0])
    call feedkeys("\<C-x>\<C-o>")
  else
    " As the default action of <C-x><C-o> causes a 'pattern not found'
    " when the result is empty, which break our input, that's really painful...
    call ClangComplete(0, ClangComplete(1, 0))
    if exists('b:clang_diags') && exists('s:clang_diags_mode') && exists('s:clang_diags_height')
      call s:ShowDiagnosticsAndClear(b:clang_diags,
      \   s:clang_diags_mode, s:clang_diags_height, g:clang_statusline)
    endif
  endif
endf
" }}}
"{{{ ClangComplete
" More about @findstart and @base to check :h omnifunc
" Async mode states:
"     ready -> busy -> sync -> ready
" Sync mode states:
"     ready -> busy -> ready
" Buffer varialbe:
"    b:clang_state => {
"      'state' : 'ready' | 'busy' | 'sync',
"      'stdout': [],
"      'stderr': [],
"    }
"    b:clang_cache => {
"      'line'    : 0,  // previous completion line number
"      'col'     : 0,  // previous completion column number
"      'getline' : ''  // previous completion line content
"      'completions': [] // parsed completion result
"      'diagnostics': [] // diagnostics info
"    }
"    b:clang_diags =>
"        A deep copy of b:clang_cache['diagnostics'] used to be shown in
"        diagnostics' window.
func! ClangComplete(findstart, base)
  if a:findstart
    if !exists('b:clang_state')
      let b:clang_state = { 'state': 'ready', 'stdout': [], 'stderr': [] }
    endif
    if b:clang_state['state'] == 'busy'  " re-enter async mode, clang is busy
      return -3
    endif
    
    let [l:start, l:base] = s:ParseCompletePoint()
    if l:start < 0
      return l:start  " this is the cancel mode
    endif
    
    let l:line    = line('.')
    let l:col     = l:start + 1
    let l:getline = getline('.')[0 : l:col-2]
    " echom printf("line: %s, col: %s, getline: %s", l:line, l:col, l:getline)
    
    " Cache parsed result into b:clang_cache
    " Reparse source file when:
    "   * first time
    "   * completion point changed
    "   * completion line content changed
    "   * has errors
    " FIXME Update of cache may be delayed when the context is changed but the
    " completion point is same with old one.
    " Someting like md5sum to check source ?
    if !exists('b:clang_cache') || b:clang_state['state'] == 'sync'
          \ || b:clang_cache['col']     !=  l:col
          \ || b:clang_cache['line']    !=  l:line
          \ || b:clang_cache['getline'] !=# l:getline
          \ || ! empty(b:clang_cache['diagnostics'])
      let b:clang_cache = {'col': l:col, 'line': l:line, 'getline': l:getline}
      " update state machine
      if b:clang_state['state'] == 'ready'
        let b:clang_state['state'] = 'busy'
        silent update " buggy when update in the second phase ?
        call s:ExecuteClang(b:clang_root, g:clang_exec, b:clang_options, l:line, l:col, g:clang_vim_exec)
      elseif b:clang_state['state'] == 'sync'
        let b:clang_state['state'] = 'ready'
      endif
      " update diagnostics info
      let b:clang_cache['completions'] = [] " empty completions
      let b:clang_cache['diagnostics'] = b:clang_state['stderr']
      let b:clang_diags = deepcopy(b:clang_cache['diagnostics'])
    endif
    if b:clang_state['state'] == 'busy'  " start async mode, need to wait the call back
      return -3
    endif
    " update completions by new l:base
    let b:clang_cache['completions'] = s:ParseCompletionResult(b:clang_state['stdout'], l:base)
    return l:start
  else
    " Simulate CompleteDone event, see ClangCompleteInit().
    " b:clang_isCompleteDone_X is valid only when CompleteDone event is not available.
    let b:clang_isCompleteDone_0 = 1
    let b:clang_isCompleteDone_1 = 1
    if exists('b:clang_cache')
      return b:clang_cache['completions']
    else
      return []
  endif
endf
"}}}

" vim: set shiftwidth=2 softtabstop=2 tabstop=2:

