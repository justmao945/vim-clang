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
"  - g:clang_diags
"       This option is a string combined with split mode, colon, and max height
"       of split window. Colon and max height are optional.
"       e.g.
"         let g:clang_diags = 'b:rightbelow:6'
"         let g:clang_diags = 'b:rightbelow'
"         let g:clang_diags = ''   " <- this disable diagnostics
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
"       Note: Only find this file in current dir ".", parent dir ".." and last 
"             in "../include" dir. If it is not in mentioned dirs, it must be 
"             defined in the dotclang file "-include-pch /path/to/stdafx.h.pch"
"             Additionally, only find PCH file stdafx for C++, but not for C.
"
" Commands:
"  - ClangGenPCHFromFile <stdafx.h>
"       Generate PCH file from the give file name <stdafx.h>, which can be %
"       (aka current file name).
"
" Note:
"   1. Make sure clang is available in path when g:clang_exec is empty
"   2. Set completeopt+=preview to show prototype in preview window
"
" TODO
"   1. Private members filter
"   2. Super tab? :h completeopt
"   3. Highlight diag window
"   4. Remove OmniComplete .... Pattern Not Found error?...
"   5. Test cases
"
" Refs:
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

if !exists('g:clang_diags')
  let g:clang_diags = 'b:rightbelow:6'
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
    if l:line[0] == ' '   " FIXME Not sure dirs start with a space?
      call add(l:res, l:line[1:-1])
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
    echo 'Not a C/C++ header: ' . l:header
  endif

  let l:pwd = fnamemodify(l:header, ':p:h')
  if !empty(l:pwd)
    exe 'cd ' . l:pwd
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
  "current window
  let l:cbuf = bufnr('%')
  let l:cft  = &filetype
  wincmd k
  " There's no window above current window
  if bufnr('%') == l:cbuf
    return
  endif
  
  " new window
  exe 'resize ' . (line('$') - 1)
  if l:cft !=# &filetype
    exe 'set filetype=' . l:cft
    setl nobuflisted
  endif

  " back to current window
  exe bufwinnr(l:cbuf) . 'wincmd w'
endf
"}}}


" {{{ s:Complete[Dot|Arrow|Colon]
" Tigger g:clang_auto_cmd when cursor is after . -> and ::
"
func! s:CompleteDot()
  if g:clang_auto && getline('.') !~# '^\s*#include'
    return '.' . g:clang_auto_cmd
  endif
  return '.'
endf

func! s:CompleteArrow()
  if g:clang_auto && getline('.')[col('.') - 2] == '-'
    return '>' . g:clang_auto_cmd
  endif
  return '>'
endf

func! s:CompleteColon()
  if g:clang_auto && getline('.')[col('.') - 2] == ':'
    return ':' . g:clang_auto_cmd
  endif
  return ':'
endf
"}}}


"{{{ s:ShowDiagnostics
" Split a window to show clang diagnostics. If there's no diagnostic, close
" the split window.
"
" @diags A list of lines from clang diagnostics
" @mode  Split policy indicators and their corresponding modes are:
"       't:topleft'   :split SCREEN horizontally, with new split on the top
"       't:botright'  :split SCREEN horizontally, with new split on the bottom
"       'b:rightbelow':split VIEWPORT horizontally, with new split on the bottom
"       'b:leftabove' :split VIEWPORT horizontally, with new split on the top
" @maxheight Maximum window height.
" @return
func! s:ShowDiagnostics(diags, mode, maxheight)
  if type(a:diags) != type([])
    echo 'Invalid arg ' . a:diags
    return
  endif
  
  " according to mode, create t: or b: var
  if a:mode[0] ==# 'b'
    if !exists('b:diags_bufnr') || !bufexists(b:diags_bufnr)
      let b:diags_bufnr = bufnr('ClangDiagnostics', 1)
    endif
    let l:diags_bufnr = b:diags_bufnr
  else
    if !exists('t:diags_bufnr') || !bufexists(t:diags_bufnr)
      let t:diags_bufnr = bufnr('ClangDiagnostics', 1)
    endif
  endif
  let l:sp = a:mode[2:-1]
  let l:cbuf = bufnr('%')

  let l:diags_winnr = bufwinnr(l:diags_bufnr)
  if l:diags_winnr == -1
    if !empty(a:diags)  " split a new window
      exe 'silent keepalt keepjumps ' .l:sp. ' sbuffer ' .l:diags_bufnr
    else
      return
    endif
  else " goto diag window
    exe l:diags_winnr . 'wincmd w'
    if empty(a:diags) " hide the diag window and !!RETURN!!
      hide
      return
    endif
  endif

  let l:height = len(a:diags)
  if a:maxheight < l:height
    let l:height = a:maxheight
  endif

  " the last line will be showed in status line as file name
  exe 'silent resize '. (l:height - 1)

  setl modifiable
  silent 1,$ delete _   " clear buffer before write
  
  for l:line in a:diags
    call append(line('$')-1, l:line)
  endfor

  " change file name to the last line of diags and goto line 1
  exe 'file ' . escape(a:diags[-1], ' \')
  silent 1

  setl buftype=nofile bufhidden=hide
  setl noswapfile nobuflisted nowrap nonumber nospell noinsertmode nomodifiable
  setl cursorline
  setl colorcolumn=-1

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
  let l:dotclang = findfile(g:clang_dotfile, expand('%:p:h') . ';')

  " clang root(aka .clang located directory) for current buffer
  " or empty that means $HOME
  let b:clang_root = fnamemodify(l:dotclang, ':p:h')

  " Firstly, add clang options for current buffer file
  let b:clang_options = ''
  if l:dotclang != ''
    let l:opts = readfile(l:dotclang)
    for l:opt in l:opts
      let b:clang_options .= ' ' . l:opt
    endfor
  endif

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

  " try to find PCH files in ., .., and ../include
  " Or add `-include-pch /path/to/x.h.pch` into the root file .clang manully
  if &filetype ==# 'cpp' && b:clang_options !~# '-include-pch'
    let l:pwd = expand('%:p:h')
    let l:afx = findfile(g:clang_stdafx_h,
          \ join([l:pwd, l:pwd.'/..', l:pwd.'/../include'], ','))
    if !empty(l:afx)
      let b:clang_options .= ' -include-pch ' . l:afx.'.pch'
    endif
  endif

  setl completefunc=ClangComplete
  setl omnifunc=ClangComplete

  " Auto completion
  inoremap <expr> <buffer> . <SID>CompleteDot()
  inoremap <expr> <buffer> > <SID>CompleteArrow()
  if &filetype == 'cpp'
    inoremap <expr> <buffer> : <SID>CompleteColon()
  endif

  " Automatically resize preview window after completion.
  " Default assume preview window is above of the editing window.
  if &completeopt =~ 'preview'
    au CompleteDone <buffer> call <SID>ShrinkPrevieWindow()
  endif

  " Automatically show clang diagnostics after completion.
  " Window is shared by buffers in the same tabpage,
  " and viewport is private for every source buffer.
  " Note: b:diags is created in ClangComplete(...)
  if g:clang_diags =~# '^[bt]:[a-z]\+\(:[0-9]\+\)\?$'
    let s:i = stridx(g:clang_diags, ':', 2)
    au CompleteDone <buffer> call <SID>ShowDiagnostics(b:diags,
        \ g:clang_diags[0 : s:i-1], g:clang_diags[s:i+1 : -1])
  endif
endf
"}}}


"{{{ ClangComplete
" Complete main routine, valid cases are showed as below.
" Note: 1. This will not parse previous lines, which means that only care
"       current line.
"       2. Clang diagnostics will be saved to b:diags after completion.
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
"
" TODO Cross line completion ? Because C/C++ is not strict with ` ` and '\n'
"
func! ClangComplete(findstart, base)
  if a:findstart
    let b:line = getline('.')
    let l:start = col('.') - 1 " start column
    
    "trim right spaces
    while l:start > 0 && b:line[l:start - 1] =~ '\s'
      let l:start -= 1
    endwhile
    
    let l:col = l:start
    let b:compat = l:start + 1 " store current completion point
    while l:col > 0 && b:line[l:col - 1] =~# '[_0-9a-zA-Z]'  " find valid ident
      let l:col -= 1
    endwhile
    
    let b:base = ''  " base word to filter completions
    if l:col < l:start " may exist <IDENT>
      if b:line[l:col] =~# '[a-zA-Z]' "<ident> doesn't start with a number
        let b:base = b:line[l:col : l:start-1]
        let l:start = l:col " reset l:start in case 1
      else
        echo 'Can not complete after an invalid identifier <'
            \. b:line[l:col : l:start-1] . '>'
        return -3
      endif
    endif
    
    " trim right spaces
    while l:col > 0 && b:line[l:col -1] =~ '\s'
      let l:col -= 1
    endwhile
   
    let l:ismber = 0
    if b:line[l:col - 1] == '.'
        \ || (b:line[l:col - 1] == '>' && b:line[l:col - 2] == '-')
        \ || (&filetype == 'cpp' && 
        \     b:line[l:col - 1] == ':' && b:line[l:col - 2] == ':')
      let l:start  = l:col
      let b:compat = l:col + 1
      let l:col -= 2
      let l:ismber = 1
    endif
    if b:line[l:col - 1] == '.'
      let l:col += 1
    endif
    
    if b:compat == 1
      "Nothing to complete, blank line completion is not supported...
      return -3
    endif
    
    if ! l:ismber && b:base == ''
      "Noting to complete, pattern completion is not supported...
      return -3
    endif
    
    " buggy when update in the second phase ?
    silent update
    return l:start
  else
    
    let b:lineat = line('.')
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
          \ || b:compat_old != b:compat
          \ || b:lineat_old != b:lineat
          \ || b:line_old !=# b:line[0 : b:compat-2]
          \ || b:diags_haserr
      exe 'cd ' . b:clang_root
      let l:command = g:clang_exec.' -cc1 -fsyntax-only -code-completion-macros'
            \ .' -code-completion-at='.expand('%:t').':'.b:lineat.':'.b:compat
            \ .' '.b:clang_options.' '.expand('%:p:.')
      let b:lineat_old = b:lineat
      let b:compat_old = b:compat
      let b:line_old   = b:line[0 : b:compat-2]
      let b:clang_output = split(system(l:command), "\n")
      
      " Completions always comes after errors and warnings
      let l:i = 0
      let b:diags = []
      for l:line in b:clang_output
        if l:line =~# '^COMPLETION:' " parse completions
          break
        else " Write info to split window
          call add(b:diags, l:line)
        endif
        let l:i += 1
      endfor
      
      " FIXME add warning and note ?
      if !empty(b:diags) && b:diags[-1] =~ 'error'
        let b:diags_haserr = 1
      else
        let b:diags_haserr = 0
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
      
      if l:word !~# '^' . b:base || l:word =~# '(Hidden)$'
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
      else
      endif
    endfor
    return l:res
  endif
endf
"}}}


