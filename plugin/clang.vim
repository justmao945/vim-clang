"{{{ Description
" Script Name: clang.vim
" Version:     1.0.0-beta (2013-xx-xx)
" Authors:     2013~     Jianjun Mao <justmao945@gmail.com>
"
" Description: Use of clang to parse in C/C++ source files.
" Notes:
"   1. Make sure `clang` is available in path when g:clang_exec is empty
"
"   2. Make sure `vim` is available in path if uses asynchronized mode(default)
"     if g:clang_vim_exec is empty.
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

if !exists('g:clang_c_completeopt')
  let g:clang_c_completeopt = 'longest,menuone'
endif

if !exists('g:clang_cpp_options')
  let g:clang_cpp_options = ''
endif

if !exists('g:clang_cpp_completeopt')
  let g:clang_cpp_completeopt = 'longest,menuone,preview'
endif

if !exists('g:clang_debug')
  let g:clang_debug = 0
endif

if !exists('g:clang_diagsopt') || g:clang_diagsopt !~# '^[a-z]\+\(:[0-9]\)\?$'
  let g:clang_diagsopt = 'rightbelow:6'
endif

if !exists('g:clang_dotfile')
  let g:clang_dotfile = '.clang'
endif

if !exists('g:clang_dotfile_overwrite')
  let g:clang_dotfile_overwrite = '.clang.ow'
endif

if !exists('g:clang_exec')
  let g:clang_exec = 'clang'
endif

if !exists('g:clang_include_sysheaders')
  let g:clang_include_sysheaders = 1
endif

if !exists('g:clang_pwheight')
  let g:clang_pwheight = 4
endif

if !exists('g:clang_sh_exec')
  " TODO: Need bash or sh on Microsoft Windows, cmd.exe is not supported.
  let g:clang_sh_exec = 'sh'
endif

if !exists('g:clang_statusline')
  let g:clang_statusline='%s\ \|\ %%l/\%%L\ \|\ %%p%%%%'
endif

if !exists('g:clang_stdafx_h')
  let g:clang_stdafx_h = 'stdafx.h'
endif

if !exists('g:clang_vim_exec')
  if has('mac')
    let g:clang_vim_exec = 'mvim'
  else
    let g:clang_vim_exec = 'vim'
  endif
endif

" Init on c/c++ files
au FileType c,cpp call <SID>ClangCompleteInit(0)
"}}}
"{{{ s:PDebug
" Uses 'echom' to preserve @info when g:clang_debug is not 0.
" Call ':messages' to see debug info
" @head Prefix of debug info
" @info Can be a string list, string, or dict
" @lv   Debug level, write info only when lv < g:clang_debug, deault is 1
func! s:PDebug(head, info, ...)
  let l:lv = a:0 > 0 && a:1 > 1 ? a:1 : 1
  if l:lv <= g:clang_debug
    echom printf("Clang: debug: %s >>> %s", string(a:head), string(a:info))
  endif
endf
"}}}
"{{{ s:PError
" Uses 'echoe' to preserve @err
" Call ':messages' to see error messages
" @head Prefix of error message
" @err Can be a string list, string, or dict
func! s:PError(head, err)
  echoe printf("Clang: error: %s >>> %s", string(a:head), string(a:err))
endf
"}}}
"{{{ s:PLog
" Uses 'echom' to preserve @info.
" @head Prefix of log info
" @info Can be a string list, string, or dict
func! s:PLog(head, info)
  echom printf("Clang: log: %s >>> %s", string(a:head), string(a:info))
endf
"}}}
" {{{ s:Complete[Dot|Arrow|Colon]
" Tigger a:cmd when cursor is after . -> and ::

func! s:ShouldComplete()
  if getline('.') =~# '#\s*\(include\|import\)' || getline('.')[col('.') - 2] == "'"
    return 0
  endif
  if col('.') == 1
    return 1
  endif
  for id in synstack(line('.'), col('.') - 1)
    if synIDattr(id, 'name') =~# 'Comment\|String\|Number\|Char\|Label\|Special'
      return 0
    endif
  endfor
  return 1
endf

func! s:CompleteDot()
  if s:ShouldComplete()
    call s:PDebug("s:CompleteDot", 'do')
    return ".\<C-x>\<C-o>"
  endif
  return '.'
endf

func! s:CompleteArrow()
  if s:ShouldComplete() && getline('.')[col('.') - 2] == '-'
    call s:PDebug("s:CompleteArrow", "do")
    return ">\<C-x>\<C-o>"
  endif
  return '>'
endf

func! s:CompleteColon()
  if s:ShouldComplete() && getline('.')[col('.') - 2] == ':'
    call s:PDebug("s:CompleteColon", "do")
    return ":\<C-x>\<C-o>"
  endif
  return ':'
endf
"}}}
" {{{ s:DeleteAfterReadTmps
" @tmps Tmp files name list
" @return a list of read files
func! s:DeleteAfterReadTmps(tmps)
  call s:PDebug("s:DeleteAfterReadTmps", a:tmps)
  if type(a:tmps) != type([])
    call s:PError("s:DeleteAfterReadTmps", "Invalid arg: ". string(a:tmps))
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
  let l:command = printf('echo | %s -fsyntax-only -v %s - 2>&1', a:clang, a:options)
  call s:PDebug("s:DiscoverIncludeDirs::cmd", l:command, 2)
  let l:clang_output = split(system(l:command), "\n")
  call s:PDebug("s:DiscoverIncludeDirs::raw", l:clang_output, 3)
  
  let l:i = 0
  let l:hit = 0
  for l:line in l:clang_output
    if l:line =~# '^#include'
      let l:hit = 1
    elseif l:hit
      break
    endif
    let l:i += 1
  endfor
  
  let l:clang_output = l:clang_output[l:i : -1]
  let l:res = []
  for l:line in l:clang_output
    if l:line[0] == ' '
      " a dirty workaround for Mac OS X (see issue #5)
      let l:path=substitute(l:line[1:-1], ' (framework directory)$', '', 'g')
      call add(l:res, l:path)
    elseif l:line =~# '^End'
      break
    endif
  endfor
  call s:PDebug("s:DiscoverIncludeDirs::parsed", l:res, 2)
  return l:res
endf
"}}}
""{{{ s:DiagnosticsWindowClose
" Close diagnostics and preview window
" @pclose Call pclose if not 0
" @driver Test driver if not 0, and close the window if the driver window is
"         not exist.
"
" Tab variable
"   t:clang_diags_bufnr
"   t:clang_diags_driver_bufnr
func! s:DiagnosticsWindowClose(pclose, driver)
 " close preview window
  if a:pclose && s:HasPreviewAbove()
    pclose
  endif
  if exists('t:clang_diags_bufnr')
    let l:cwn = bufwinnr(bufnr('%'))
    let l:dwn = bufwinnr(t:clang_diags_bufnr)
    if l:dwn != -1 && (!a:driver || (a:driver && bufwinnr(t:clang_diags_driver_bufnr) == -1))
      exe l:dwn . 'wincmd w'
      call s:PDebug("s:DiagnosticsWindowClose", l:dwn)
      hide
      exe l:cwn . 'wincmd w'
    endif
  endif
  return -1
endf
"}}}
"{{{ s:DiagnosticsWindowOpen
" Split a window to show clang diagnostics. If there's no diagnostics, close
" the split window.
" Global variable:
"   g:clang_diagsopt
"   g:clang_statusline
" Tab variable
"   t:clang_diags_bufnr         <= diagnostics window bufnr
"   t:clang_diags_driver_bufnr  <= the driver buffer numer
"   NOTE: Don't use winnr, winnr maybe changed.
" @diags A list of lines from clang diagnostics, or a diagnostics file name.
" @return -1 or buffer number t:clang_diags_bufnr
func! s:DiagnosticsWindowOpen(diags)
  let l:diags = a:diags
  if type(l:diags) == type('')
    " diagnostics file name
    let l:diags = readfile(l:diags)
  elseif type(l:diags) != type([])
    call s:PError("s:DiagnosticsWindowOpen", 'Invalid arg ' . string(l:diags))
    return -1
  endif
  
  let l:i = stridx(g:clang_diagsopt, ':')
  let l:mode      = g:clang_diagsopt[0 : l:i-1]
  let l:maxheight = g:clang_diagsopt[l:i+1 : -1]

  " Here uses t:clang_diags_bufnr to keep only one window in a *tab*
  if !exists('t:clang_diags_bufnr') || !bufexists(t:clang_diags_bufnr)
    let t:clang_diags_bufnr = bufnr('ClangDiagnostics@' . last_buffer_nr(), 1)
  endif
  let l:cbuf = bufnr('%')

  let l:winnr = bufwinnr(t:clang_diags_bufnr)
  if l:winnr == -1
    if ! empty(l:diags)
      " split a new window, go into it automatically
      exe 'silent keepalt keepjumps keepmarks ' .l:mode. ' sbuffer ' . t:clang_diags_bufnr
      call s:PDebug("s:DiagnosticsWindowOpen::sbuffer", t:clang_diags_bufnr)
    else
      " empty result, return
      return -1
    endif
  elseif empty(l:diags)
    " just close window(but not preview window) and return
    return s:DiagnosticsWindowClose(0, 0)
  else
    " goto the exist window
    call s:PDebug("s:DiagnosticsWindowOpen::wincmd", l:winnr)
    exe l:winnr . 'wincmd w'
  endif

  " the last line will be showed in status line as file name
  let l:diags_statics = ''
  if empty(l:diags[-1]) || l:diags[-1] =~ '^[0-9]\+\serror\|warn\|note'
    let l:diags_statics = l:diags[-1]
    let l:diags = l:diags[0: -2]
  endif

  let l:height = min([len(l:diags), l:maxheight])
  exe 'silent resize '. l:height

  setl modifiable
  " clear buffer before write
  silent 1,$ delete _

  " add diagnostics
  for l:line in l:diags
    call append(line('$')-1, l:line)
  endfor
  " the last empty line
  $delete _

  " goto the 1st line
  silent 1
    
  setl buftype=nofile bufhidden=hide
  setl noswapfile nobuflisted nowrap nonumber nospell nomodifiable winfixheight winfixwidth
  setl cursorline
  setl colorcolumn=-1
  
  " Don't use indentLine in the diagnostics window
  " See https://github.com/Yggdroot/indentLine.git
  if exists('b:indentLine_enabled') && b:indentLine_enabled
    IndentLinesToggle
  endif

  syn match ClangSynDiagsError    display 'error:'
  syn match ClangSynDiagsWarning  display 'warning:'
  syn match ClangSynDiagsNote     display 'note:'
  syn match ClangSynDiagsPosition display '^\s*[~^ ]\+$'
  
  hi ClangSynDiagsError           guifg=Red     ctermfg=9
  hi ClangSynDiagsWarning         guifg=Magenta ctermfg=13
  hi ClangSynDiagsNote            guifg=Gray    ctermfg=8
  hi ClangSynDiagsPosition        guifg=Green   ctermfg=10

  " change file name to the last line of diags and goto line 1
  exe printf('setl statusline='.g:clang_statusline, escape(l:diags_statics, ' \'))

  " back to current window, aka the driver window
  let t:clang_diags_driver_bufnr = l:cbuf
  exe bufwinnr(l:cbuf) . 'wincmd w'
  return t:clang_diags_bufnr
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
  if a:header !~? '.h'
    let cho = confirm('Not a C/C++ header: ' . a:header . "\n" .
          \ 'Continue to generate PCH file ?',
          \ "&Yes\n&No", 2)
    if cho != 1 | return | endif
  endif
 
  let l:header      = shellescape(expand(a:header))
  let l:header_pch  = shellescape(a:header . ".pch")
  let l:command = printf('%s -cc1 %s -emit-pch -o %s %s', a:clang, a:options, l:header_pch, l:header)
  call s:PDebug("s:GenPCH::cmd", l:command, 2)
  let l:clang_output = system(l:command)

  if v:shell_error
    call s:DiagnosticsWindowOpen(split(l:clang_output, '\n'))
    call s:PDebug("s:GenPCH", {'exit': v:shell_error, 'cmd': l:command, 'out': l:clang_output })
  else
    call s:PLog("s:GenPCH", 'Clang creates PCH flie ' . l:header . '.pch successfully!')
  endif
  return l:clang_output
endf
"}}}
" {{{ s:GlobalVarSet
" Set global vim options for clang and return old values
" @return old values
func! s:GlobalVarSet()
  let l:values = {
      \ 'shell':        &shell,
      \ 'completeopt':  &completeopt,
  \ }
  if !empty(g:clang_sh_exec)
    exe 'set shell='.g:clang_sh_exec
  endif
  if &filetype == 'c' && !empty(g:clang_c_completeopt)
    exe 'set completeopt='.g:clang_c_completeopt
  elseif &filetype == 'cpp' && !empty(g:clang_cpp_completeopt)
    exe 'set completeopt='.g:clang_cpp_completeopt
  endif
  return l:values
endf
" }}}
" {{{ s:GlobalVarRestore
" Restore global vim options
func! s:GlobalVarRestore(values)
  if type(a:values) != type({})
    s:PError('GlobalVarRestore', 'invalid arg type')
    return
  endif
  exe 'set shell='.a:values['shell']
  exe 'set completeopt='.a:values['completeopt']
endf
" }}}
" {{{ s:HasPreviewAbove
" 
" Detect above view is preview window or not.
"
func! s:HasPreviewAbove()
  let l:cbuf = bufnr('%')
  let l:has = 0
  " goto above
  wincmd k
  if &completeopt =~ 'preview' && &previewwindow
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

    " end of base word to filter completions
    let l:base = ''
    if l:col < l:start
      " may exist <IDENT>
      if l:line[l:col] =~# '[_a-zA-Z]'
        "<ident> doesn't start with a number
        let l:base = l:line[l:col : l:start-1]
        " reset l:start in case 1
        let l:start = l:col
      else
        call s:PError("s:ParseCompletePoint", 'Can not complete after an invalid identifier <'
            \. l:line[l:col : l:start-1] . '>')
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
    call s:PDebug("s:ParseCompletePoint", printf("start: %s, base: %s", l:start, l:base))
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
          \ 'menu': l:has_preview ? '' : l:word ==# l:proto ? '' : l:proto,
          \ 'info': l:proto,
          \ 'dup' : 1 })
    elseif !empty(l:res)
      " overload functions, for C++
      let l:res[-1]['info'] .= "\n" . l:proto
    endif
  endfor

  return l:res
endf
" }}}
"{{{ s:ShrinkPrevieWindow
" Shrink preview window to fit lines.
" Assume cursor is in the editing window, and preview window is above of it.
" Global variable
"   g:clang_pwheight
"   g:clang_statusline
func! s:ShrinkPrevieWindow()
  if &completeopt !~ 'preview'
    return
  endif

  "current view
  let l:cbuf = bufnr('%')
  let l:cft  = &filetype
  " go to above view
  wincmd k
  if &previewwindow
    " enhence the preview window
    if empty(getline('$'))
      " delete the last empty line
      setl modifiable
      $delete _
      setl nomodifiable
    endif
    let l:height = min([line('$'), g:clang_pwheight])
    exe 'resize ' . l:height
    call s:PDebug("s:ShrinkPrevieWindow::height", l:height)
    if l:cft != &filetype
      exe 'set filetype=' . l:cft
      setl nobuflisted
      exe printf('setl statusline='.g:clang_statusline, 'Prototypes')
    endif
    " goto the 1st line
    silent 1
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
"     b:clang_isCompleteDone_0  => used when CompleteDone event not available
"     b:clang_options => parepared clang cmd options
"     b:clang_options_noPCH  => same as b:clang_options except no pch options
"     b:clang_root => project root to run clang
func! s:ClangCompleteInit(force)
  " omnifunc may be overwritten by other actions.
  setl completefunc=ClangComplete
  setl omnifunc=ClangComplete

  if ! exists('b:clang_complete_inited')
    let b:clang_complete_inited = 1
  elseif ! a:force
    return
  endif

  call s:PDebug("s:ClangCompleteInit", "start")
  let l:gvars = s:GlobalVarSet()

  let l:cwd = fnameescape(getcwd())
  let l:fwd = fnameescape(expand('%:p:h'))
  exe 'lcd ' . l:fwd
  let l:dotclang    = findfile(g:clang_dotfile, '.;')
  let l:dotclangow  = findfile(g:clang_dotfile_overwrite, '.;')

  " Firstly, add clang options for current buffer file
  let b:clang_options = ''

  let l:is_ow = 0
  if filereadable(l:dotclangow)
    let l:is_ow = 1
    let l:dotclang = l:dotclangow
  endif

  " clang root(aka .clang located directory) for current buffer
  if filereadable(l:dotclang)
    let b:clang_root = fnameescape(fnamemodify(l:dotclang, ':p:h'))
    let l:opts = readfile(l:dotclang)
    for l:opt in l:opts
      let b:clang_options .= ' ' . l:opt
    endfor
  else
    " or means source file directory
    let b:clang_root = l:fwd
  endif
  exe 'lcd '.l:cwd

  " Secondly, add options defined by user if is not ow
  if &filetype == 'c'
    let b:clang_options .= ' -x c '
    if ! l:is_ow
      let b:clang_options .= g:clang_c_options
    endif
  elseif &filetype == 'cpp'
    let b:clang_options .= ' -x c++ '
    if ! l:is_ow
      let b:clang_options .= g:clang_cpp_options
    endif
  endif
  
  " add include directories if is enabled and not ow
  if g:clang_include_sysheaders && ! l:is_ow
    let l:incs = s:DiscoverIncludeDirs(g:clang_exec, b:clang_options)
    for l:dir in l:incs
      let b:clang_options .= ' -I ' . shellescape(l:dir)
    endfor
  endif
  
  " backup options without PCH support
  let b:clang_options_noPCH = b:clang_options

  " Create GenPCH command
  com! -nargs=* ClangGenPCHFromFile call <SID>GenPCH(g:clang_exec, b:clang_options_noPCH, <f-args>)
  
  " Create close diag window command
  com! ClangClosePreviewDiagWindow  call <SID>DiagnosticsWindowClose(1,0)

  " Useful to re-initialize plugin if .clang is changed
  com! ClangCompleteInit            call <SID>ClangCompleteInit(1)

  " try to find PCH files in clang_root and clang_root/include
  " Or add `-include-pch /path/to/x.h.pch` into the root file .clang manully
  if &filetype == 'cpp' && b:clang_options !~# '-include-pch'
    let l:cwd = fnameescape(getcwd())
    exe 'lcd ' . b:clang_root
    let l:afx = findfile(g:clang_stdafx_h, '.;./include') . '.pch'
    if filereadable(l:afx)
      let b:clang_options .= ' -include-pch ' . shellescape(l:afx)
    endif
    exe 'lcd '.l:cwd
  endif

  if g:clang_auto   " Auto completion
    inoremap <expr> <buffer> . <SID>CompleteDot()
    inoremap <expr> <buffer> > <SID>CompleteArrow()
    if &filetype == 'cpp'
      inoremap <expr> <buffer> : <SID>CompleteColon()
    endif
  endif

  " CompleteDone event is available since version 7.3.598
  if exists("##CompleteDone")
    au CompleteDone <buffer> call <SID>PDebug("##CompleteDone", "triggered")
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

  " Close diagnostics window when enter new buffer window, and must test
  " the driver state, user may not hope close the window if the driver is
  " still available.
  "  FIXME buffer unload or leave events may cause vim SEGV...
  au BufWinEnter <buffer> call <SID>DiagnosticsWindowClose(1,1)

  call s:GlobalVarRestore(l:gvars)
endf
"}}}
"{{{ s:ClangExecute
" Execute clang binary to generate completions and diagnostics.
" Global variable:
"     g:clang_exec
"     g:clang_vim_exec
"
" Buffer vars:
"     b:clang_state => {
"       'state' :  // updated to 'ready' in sync mode
"       'stdout':  // updated in sync mode
"       'stderr':  // updated in sync mode
"     }
" @root Clang root, project directory
" @clang_options Options appended to clang binary image
" @line Line to complete
" @col Column to complete
" @return [completion, diagnostics]
func! s:ClangExecute(root, clang_options, line, col)
  let l:cwd = fnameescape(getcwd())
  exe 'lcd ' . a:root
  let l:src = shellescape(expand('%:p:.'))
  let l:command = printf('%s -cc1 -fsyntax-only -code-completion-macros -code-completion-at=%s:%d:%d %s %s',
                      \ g:clang_exec, l:src, a:line, a:col, a:clang_options, l:src)
  let l:tmps = [tempname(), tempname()]
  let l:command .= ' 1>'.l:tmps[0].' 2>'.l:tmps[1]
  let l:res = [[], []]
  if !exists('v:servername') || empty(v:servername)
    let b:clang_state['state'] = 'ready'
    call s:PDebug("s:ClangExecute::cmd", l:command, 2)
    call system(l:command)
    let l:res = s:DeleteAfterReadTmps(l:tmps)
    call s:PDebug("s:ClangExecute::stdout", l:res[0], 3)
    call s:PDebug("s:ClangExecute::stderr", l:res[1], 2)
  else
    " Please note that '--remote-expr' executes expressions in server, but
    " '--remote-send' only sends keys, which is same as type keys in server...
    " Here occurs a bug if uses '--remote-send', the 'col(".")' is not right.
    let l:keys = printf('ClangExecuteDone("%s","%s")', l:tmps[0], l:tmps[1])
    let l:vcmd = printf('%s -s --noplugin --servername %s --remote-expr %s',
                      \ g:clang_vim_exec, shellescape(v:servername), shellescape(l:keys))
    let l:command = '('.l:command.';'.l:vcmd.') &'
    call s:PDebug("s:ClangExecute::cmd", l:command, 2)
    call system(l:command)
  endif
  exe 'lcd ' . l:cwd
  let b:clang_state['stdout'] = l:res[0]
  let b:clang_state['stderr'] = l:res[1]
  return l:res
endf
"}}}
" {{{ ClangExecuteDone
" Called by vim-client when clang is returned in asynchronized mode.
"
" Buffer vars:
"     b:clang_state => {
"       'state' :  // updated to 'sync' in async mode
"       'stdout':  // updated in async mode
"       'stderr':  // updated in async mode
"     }
func! ClangExecuteDone(tmp1, tmp2)
  let l:res = s:DeleteAfterReadTmps([a:tmp1, a:tmp2])
  let b:clang_state['state'] = 'sync'
  let b:clang_state['stdout'] = l:res[0]
  let b:clang_state['stderr'] = l:res[1]
  call s:PDebug("ClangExecuteDone::stdout", l:res[0], 3)
  call s:PDebug("ClangExecuteDone::stderr", l:res[1], 2)
  call feedkeys("\<Esc>a")
  " As the default action of <C-x><C-o> causes a 'pattern not found'
  " when the result is empty, which break our input, that's really painful...
  if ! empty(l:res[0])
    call feedkeys("\<C-x>\<C-o>")
  else
    call ClangComplete(0, ClangComplete(1, 0))
  endif
endf
" }}}
"{{{ ClangComplete
" More about @findstart and @base to check :h omnifunc
" Async mode states:
"     ready -> busy -> sync -> ready
" Sync mode states:
"     ready -> busy -> ready
" Buffer variable:
"    b:clang_state => {
"      'state' : 'ready' | 'busy' | 'sync',
"      'stdout': [],
"      'stderr': [],
"    }
"    b:clang_cache => {
"      'line'    : 0,   // previous completion line number
"      'col'     : 0,   // previous completion column number
"      'getline' : '',  // previous completion line content
"      'completions': [], // parsed completion result
"      'diagnostics': [], // diagnostics info
"    }
func! ClangComplete(findstart, base)
  call s:PDebug("ClangComplete", "start")

  let l:gvars = s:GlobalVarSet()

  if a:findstart
    call s:PDebug("ClangComplete", "phase 1")
    " close preview window not owned by this view before completion
    if ! s:HasPreviewAbove()
      pclose
    endif
    if !exists('b:clang_state')
      let b:clang_state = { 'state': 'ready', 'stdout': [], 'stderr': [] }
    endif
    if b:clang_state['state'] == 'busy'
      " re-enter async mode, clang is busy
      return -3
    endif
    
    let [l:start, l:base] = s:ParseCompletePoint()
    if l:start < 0
      " this is the cancel mode
      return l:start
    endif
    
    let l:line    = line('.')
    let l:col     = l:start + 1
    let l:getline = getline('.')[0 : l:col-2]
    call s:PDebug("ClangComplete", printf("line: %s, col: %s, getline: %s", l:line, l:col, l:getline))
    
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
          \ || ! empty(b:clang_state['stderr'])
      let b:clang_cache = {'col': l:col, 'line': l:line, 'getline': l:getline}
      call s:PDebug("ClangComplete::state", b:clang_state['state'])
      " update state machine
      if b:clang_state['state'] == 'ready'
        let b:clang_state['state'] = 'busy'
        " buggy when update in the second phase ?
        silent update!
        call s:ClangExecute(b:clang_root, b:clang_options, l:line, l:col)
      elseif b:clang_state['state'] == 'sync'
        let b:clang_state['state'] = 'ready'
      endif
      " update diagnostics info
      " empty completions
      let b:clang_cache['completions'] = []
      let b:clang_cache['diagnostics'] = b:clang_state['stderr']
    endif
    if b:clang_state['state'] == 'busy'
      " start async mode, need to wait the call back
      return -3
    endif
    
    " update completions by new l:base
    let b:clang_cache['completions'] = s:ParseCompletionResult(b:clang_state['stdout'], l:base)
    " close preview window if empty
    if empty(b:clang_cache['completions']) && s:HasPreviewAbove()
      pclose
    endif
    " call to show diagnostics
    call s:DiagnosticsWindowOpen(b:clang_cache['diagnostics'])
    return l:start
  else
    call s:PDebug("ClangComplete", "phase 2")
    " Simulate CompleteDone event, see ClangCompleteInit().
    " b:clang_isCompleteDone_X is valid only when CompleteDone event is not available.
    let b:clang_isCompleteDone_0 = 1
    if exists('b:clang_cache')
      return b:clang_cache['completions']
    else
      return []
    endif
  endif

  call s:GlobalVarRestore(l:gvars)
endf
"}}}

" vim: set shiftwidth=2 softtabstop=2 tabstop=2:

