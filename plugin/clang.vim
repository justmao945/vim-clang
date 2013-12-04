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
" Notes:
"   1. Make sure clang is available in path when g:clang_exec is empty
"
"   2. Set completeopt+=preview to show prototype in preview window.
"      But there's no local completeopt, so we use BufEnter event.
"      e.g. only for C++ sources but not for C, add
"         au BufEnter *.cc,*.cpp,*.hh,*hpp set completeopt+=preview
"         au BufEnter *.c,*.h set completeopt-=preview
"      to .vimrc
"
" TODO:
"   1. Private members filter
"   2. Remove OmniComplete .... Pattern Not Found error?...
"   3. Test cases
"
" Issues:
"   1. When complete an identifier only has a char, the char will be deleted by
"      OmniCompletion with 'longest' completeopt.
"      Vim verison: 7.3.754
"   
" References:
"   [1] http://clang.llvm.org/docs/
"   [2] VIM help file
"   [3] VIM scripts [vim-buffergator, clang_complete]
"}}}


"{{{ Global initialization
if exists('g:clang_loaded')
  finish
endif
let g:clang_loaded = 1

if !exists('g:clang_auto')
  let g:clang_auto = 1
endif

if !exists('g:clang_auto_cmd')
  let g:clang_auto_cmd = "\<C-X>\<C-O>"
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

if !exists('g:clang_diagsopt')
  let g:clang_diagsopt = 'b:rightbelow:6'
endif

if !exists('g:clang_stdafx_h')
  let g:clang_stdafx_h = 'stdafx.h'
endif

" Init on c/c++ files
au FileType c,cpp call <SID>ClangCompleteInit()
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
  let l:command = 'echo | ' . a:clang . ' -fsyntax-only -v ' . a:options . ' -'
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
      call add(l:res, '"' . l:line[1:-1] . '"')
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
  let l:header = expand(a:header)
  if l:header !~? '.h'
    let cho = confirm('Not a C/C++ header: ' . l:header . "\n" .
          \ 'Continue to generate PCH file ?',
          \ "&Yes\n&No", 2)
    if cho != 1 | return | endif
  endif
  
  let l:command = a:clang . ' -cc1 ' . a:options .
        \ ' -emit-pch -o ' . l:header.'.pch ' . l:header
  let l:clang_output = system(l:command)

  if v:shell_error
    echo 'Clang returns error ' . v:shell_error
    echo l:command
    echo l:clang_output
  else
    echo 'Clang creates PCH flie ' . l:header . '.pch successfully!'
  endif
  return l:clang_output
endf
"}}}


"{{{ s:ShrinkPrevieWindow
" Shrink preview window to fit lines.
" Assume cursor is in the editing window, and preview window is above of it.
func! s:ShrinkPrevieWindow()
  if &completeopt !~# 'preview'
    return
  endif

  "current view
  let l:cbuf = bufnr('%')
  let l:cft  = &filetype

  wincmd k " go to above view
  if( &previewwindow )
    exe 'resize ' . (line('$') - 1)
    if l:cft !=# &filetype
      exe 'set filetype=' . l:cft
      setl nobuflisted
      setl statusline=Prototypes
    endif
  endif

  " back to current window
  exe bufwinnr(l:cbuf) . 'wincmd w'
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

func! s:CompleteDot(cmd)
  if s:ShouldComplete()
    return '.' . a:cmd
  endif
  return '.'
endf

func! s:CompleteArrow(cmd)
  if s:ShouldComplete() && getline('.')[col('.') - 2] == '-'
    return '>' . a:cmd
  endif
  return '>'
endf

func! s:CompleteColon(cmd)
  if s:ShouldComplete() && getline('.')[col('.') - 2] == ':'
    return ':' . a:cmd
  endif
  return ':'
endf
"}}}


"{{{ s:ShowDiagnostics
" Split a window to show clang diagnostics. If there's no diagnostic, close
" the split window.
"
" @diags A list of lines from clang diagnostics, or a diagnostics file name.
" @mode  Split policy indicators and their corresponding modes are:
"       't:topleft'   :split SCREEN horizontally, with new split on the top
"       't:botright'  :split SCREEN horizontally, with new split on the bottom
"       'b:rightbelow':split VIEWPORT horizontally, with new split on the bottom
"       'b:leftabove' :split VIEWPORT horizontally, with new split on the top
" @maxheight Maximum window height.
" @return
func! s:ShowDiagnostics(diags, mode, maxheight)
  let l:diags = a:diags

  if type(l:diags) == type('') " diagnostics file name
    let l:diags = readfile(l:diags)
  elseif type(l:diags) != type([])
    echo 'Invalid arg ' . l:diags
    return
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
      return
    endif
  else " goto diag window
    exe l:diags_winnr . 'wincmd w'
    if empty(l:diags) " hide the diag window and !!RETURN!!
      hide
      return
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
  exe 'setl statusline=' . escape(l:diags[-1], ' \')

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
func! s:ClangCompleteInit()
  let l:cwd = escape(getcwd(), ' ')
  let l:fwd = expand('%:p:gs?\ ?\\ ?:h')
  exe 'lcd ' . l:fwd
  let l:dotclang = findfile(g:clang_dotfile, '.;')

  " Firstly, add clang options for current buffer file
  let b:clang_options = ''

  " clang root(aka .clang located directory) for current buffer
  if filereadable(l:dotclang)
    let b:clang_root = fnamemodify(l:dotclang, ':p:h')
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

  " try to find PCH files in clang_root and clang_root/include
  " Or add `-include-pch /path/to/x.h.pch` into the root file .clang manully
  if &filetype ==# 'cpp' && b:clang_options !~# '-include-pch'
    let l:cwd = escape(getcwd(), ' ')
    exe 'lcd ' . b:clang_root
    let l:afx = findfile(g:clang_stdafx_h, '.;./include') . '.pch'
    if filereadable(l:afx)
      let b:clang_options .= ' -include-pch ' . l:afx
    endif
    exe 'lcd '.l:cwd
  endif

  setl completefunc=ClangComplete
  setl omnifunc=ClangComplete

  if g:clang_auto   " Auto completion
    inoremap <expr> <buffer> . <SID>CompleteDot(g:clang_auto_cmd)
    inoremap <expr> <buffer> > <SID>CompleteArrow(g:clang_auto_cmd)
    if &filetype == 'cpp'
      inoremap <expr> <buffer> : <SID>CompleteColon(g:clang_auto_cmd)
    endif
  endif

  " CompleteDone event is available since version 7.3.598
  if exists("##CompleteDone")
    " Automatically resize preview window after completion.
    " Default assume preview window is above of the editing window.
    au CompleteDone <buffer> call <SID>ShrinkPrevieWindow()
  else
    let b:clang_isCompleteDone_0 = 0
    au CursorMovedI <buffer>
          \ if b:clang_isCompleteDone_0 |
          \   call <SID>ShrinkPrevieWindow() |
          \   let b:clang_isCompleteDone_0 = 0 |
          \ endif
  endif

  " Window is shared by buffers in the same tabpage,
  " and viewport is private for every source buffer.
  " Note: b:clang_diags is created in ClangComplete(...)
  if g:clang_diagsopt =~# '^[bt]:[a-z]\+\(:[0-9]\+\)\?$'
    let s:cd_i = stridx(g:clang_diagsopt, ':', 2)
    let s:cd_mode   = g:clang_diagsopt[0 : s:cd_i-1]
    let s:cd_height = g:clang_diagsopt[s:cd_i+1 : -1]
    let b:clang_diags = []
    if exists("##CompleteDone")
      " Automatically show clang diagnostics after completion.
      au CompleteDone <buffer> 
            \ call <SID>ShowDiagnostics(b:clang_diags, s:cd_mode, s:cd_height)
    else
      " FIXME I don't know why VIM escapes after press a key when the
      " completion pattern not found...
      let b:clang_isCompleteDone_1 = 0
      au CursorMovedI <buffer>
            \ if b:clang_isCompleteDone_1 |
            \   call <SID>ShowDiagnostics(b:clang_diags, s:cd_mode, s:cd_height) |
            \   let b:clang_isCompleteDone_1 = 0 |
            \ endif
    endif
  endif
endf
"}}}


"{{{ ClangComplete
" Complete main routine, valid cases are showed as below.
" Note: 1. This will not parse previous lines, which means that only care
"       current line.
"       2. Clang diagnostics will be saved to b:clang_diags after completion.
"
" <IDENT> indicates an identifier
" </> the completion point
" <.> including a `.` or `->` or `::`
" <s> zero or more spaces and tabs
" <*> is anything other then the new line `\n`
"
" 1  <*><IDENT><s></>         complete identfiers start with <IDENT>
" 2  <*><.><s></>             complete all members
" 3  <*><.><s><IDENT><s></>   complete identifers start with <IDENT>
"
" Completion output of clang:
"   COMPLETION: <ident> : <prototype>
"   0           12     c  c+3
"
" More about @findstart and @base to check :h omnifunc
"
" FIXME Tabs can't work corrently at ... =~ '\s' ?
" `set expandtab` is recommended
"
func! ClangComplete(findstart, base)
  if a:findstart
    let b:clang_line = getline('.')
    let l:start = col('.') - 1 " start column
    
    "trim right spaces
    while l:start > 0 && b:clang_line[l:start - 1] =~ '\s'
      let l:start -= 1
    endwhile
    
    let l:col = l:start
    while l:col > 0 && b:clang_line[l:col - 1] =~# '[_0-9a-zA-Z]'  " find valid ident
      let l:col -= 1
    endwhile
    
    let b:clang_baseword = ''  " base word to filter completions
    if l:col < l:start " may exist <IDENT>
      if b:clang_line[l:col] =~# '[_a-zA-Z]' "<ident> doesn't start with a number
        let b:clang_baseword   = b:clang_line[l:col : l:start-1]
        let l:start  = l:col " reset l:start in case 1
      else
        echo 'Can not complete after an invalid identifier <'
            \. b:clang_line[l:col : l:start-1] . '>'
        return -3
      endif
    endif
    
    " trim right spaces
    while l:col > 0 && b:clang_line[l:col -1] =~ '\s'
      let l:col -= 1
    endwhile
   
    let l:ismber = 0
    if b:clang_line[l:col - 1] == '.'
        \ || (b:clang_line[l:col - 1] == '>' && b:clang_line[l:col - 2] == '-')
        \ || (&filetype == 'cpp' && 
        \     b:clang_line[l:col - 1] == ':' && b:clang_line[l:col - 2] == ':')
      let l:start  = l:col
      let l:col -= 2
      let l:ismber = 1
    endif
    if b:clang_line[l:col - 1] == '.'
      let l:col += 1
    endif
    
    "Noting to complete, pattern completion is not supported...
    if ! l:ismber && empty(b:clang_baseword)
      return -3
    endif
    
    " buggy when update in the second phase ?
    silent update
    let b:clang_compat = l:start + 1
    return l:start
  else
    let b:clang_lineat = line('.')
    
    " Cache parsed result into b:clang_output
    " Reparse source file when:
    "   * first time
    "   * completion point changed
    "   * completion line content changed
    "   * has errors
    " FIXME Update of cache may be delayed when the context is changed but the
    " completion point is same with old one.
    " Someting like md5sum to check source ?
    if !exists('b:clang_output')
          \ || b:clang_compat_old !=  b:clang_compat
          \ || b:clang_lineat_old !=  b:clang_lineat
          \ || b:clang_line_old   !=# b:clang_line[0 : b:clang_compat-2]
          \ || b:clang_diags_haserr
      let l:cwd = escape(getcwd(), ' ')
      exe 'lcd ' . b:clang_root
      let l:src = expand('%:p:gs?\ ?\\ ?.')  " Thanks RageCooky, fix when a path has spaces.
      let l:command = g:clang_exec.' -cc1 -fsyntax-only -code-completion-macros'
            \ .' -code-completion-at='.l:src.':'.b:clang_lineat.':'.b:clang_compat
            \ .' '.b:clang_options.' '.l:src
      let b:clang_lineat_old = b:clang_lineat
      let b:clang_compat_old = b:clang_compat
      let b:clang_line_old   = b:clang_line[0 : b:clang_compat-2]
      
      " Redir clang diagnostics into a tempfile.
      " * Fix stdout/stderr buffer flush bug? of clang, that COMPLETIONs are not
      "   flushed line by line when not output to a terminal.
      " * clang on Win32 will not redirect errors to stderr?
      let l:tmp = tempname()
      if has('win32') | let l:tmp='' | endif
      if !empty(l:tmp)
        let l:command .= ' 2>' . l:tmp
      endif
      "echo l:command
      let b:clang_output = split(system(l:command), "\n")
      exe 'lcd ' . l:cwd
      
      "echo b:clang_output
      let l:i = 0
      if !empty(l:tmp)
        " FIXME Can't read file in Windows?
        let b:clang_diags = readfile(l:tmp)
        call delete(l:tmp)
      else
        " Completions always comes after errors and warnings
        let b:clang_diags = []
        for l:line in b:clang_output
          if l:line =~# '^COMPLETION:' " parse completions
            break
          else " Write info to split window
            call add(b:clang_diags, l:line)
          endif
          let l:i += 1
        endfor
      endif
      
      " The last item in b:clang_diags has statistics info of diagnostics
      if !empty(b:clang_diags) && b:clang_diags[-1] =~ 'error\|warning'
        let b:clang_diags_haserr = 1
      else
        let b:clang_diags_haserr = 0
      endif
      
      if l:i > 0
        let b:clang_output = b:clang_output[l:i : -1]
      endif
    endif
   
    let l:res = []
    let l:has_preview = &completeopt =~# 'preview'
    
    for l:line in b:clang_output
      let l:s = stridx(l:line, ':', 13)
      let l:word  = l:line[12 : l:s-2]
      let l:proto = l:line[l:s+2 : -1]
      
      if l:word !~# '^' . b:clang_baseword || l:word =~# '(Hidden)$'
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
    
    " Simulate CompleteDone event, see ClangCompleteInit().
    " b:clang_isCompleteDone_X is valid only when CompleteDone event is not available.
    let b:clang_isCompleteDone_0 = 1
    let b:clang_isCompleteDone_1 = 1
    
    if &completeopt =~# 'preview' && ! <SID>HasPreviewAbove()
      pclose " close preview window before completion
    endif
    
    return l:res
  endif
endf
"}}}


