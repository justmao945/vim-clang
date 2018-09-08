"{{{ Global initialization
if exists('g:clang_loaded')
  finish
endif
let g:clang_loaded = 1

let g:clang_has_win = has('win16') || has('win32') || has('win64') || has('win95')

" Choose a python infrastructre
if has('pythonx')
  let s:py = 'pyxfile'
elseif has('python3')
  let s:py = 'py3file'
else
  let s:py = 'pyfile'
endif

" Path to compilation_database.py
let s:compilation_database_py = fnamemodify(resolve(expand('<sfile>:p')), ':h') . '/compilation_database.py'

if !exists('g:clang_auto')
  let g:clang_auto = 1
endif

if !exists('g:clang_compilation_database')
  let g:clang_compilation_database = ''
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

if !exists('g:clang_diagsopt') || (!empty(g:clang_diagsopt) && g:clang_diagsopt !~# '^[a-z]\+\(:[0-9]\)\?$')
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

if !exists('g:clang_gcc_exec')
  let g:clang_gcc_exec = 'gcc'
endif

if !exists('g:clang_format_auto')
  let g:clang_format_auto = 0
endif

if !exists('g:clang_format_exec')
  let g:clang_format_exec = 'clang-format'
endif

if !exists('g:clang_format_style')
  let g:clang_format_style = 'LLVM'
end

if !exists('g:clang_enable_format_command')
  let g:clang_enable_format_command = 1
endif

if !exists('g:clang_check_syntax_auto')
	let g:clang_check_syntax_auto = 0
endif

if !exists('g:clang_include_sysheaders')
  let g:clang_include_sysheaders = 1
endif

if !exists('g:clang_include_sysheaders_from_gcc')
  let g:clang_include_sysheaders_from_gcc = 0
endif

if !exists('g:clang_load_if_clang_dotfile')
  let g:clang_load_if_clang_dotfile = 0
endif

if !exists('g:clang_pwheight')
  let g:clang_pwheight = 4
endif

if !exists('g:clang_sh_exec')
  if g:clang_has_win
    let g:clang_sh_exec = 'C:\Windows\system32\cmd.exe'
  else
    " sh default is dash on Ubuntu, which is unsupported
    let g:clang_sh_exec = 'bash'
  endif
endif
let g:clang_sh_is_cmd = g:clang_sh_exec =~ 'cmd.exe'

if !exists('g:clang_statusline')
  let g:clang_statusline='%s\ \|\ %%l/\%%L\ \|\ %%p%%%%'
endif

if !exists('g:clang_stdafx_h')
  let g:clang_stdafx_h = 'stdafx.h'
endif

if !exists('g:clang_use_path')
  let g:clang_use_path = 1
endif

if !exists('g:clang_vim_exec')
  if has('mac')
    let g:clang_vim_exec = 'mvim'
  elseif !g:clang_has_win && has('gui_running')
    let g:clang_vim_exec = 'gvim'
  else
    let g:clang_vim_exec = 'vim'
  endif
endif

if !exists('g:clang_verbose_pmenu')
  let g:clang_verbose_pmenu = 0
endif

" Init on c/c++ files
au FileType c,cpp call <SID>ClangCompleteInit(0)
"}}}
"{{{ s:IsValidFile
" A new file is also a valid file
func! s:IsValidFile()
  let l:cur = expand("%")
  " don't load plugin when in fugitive buffer
  if l:cur =~ 'fugitive://'
    return 0
  endif
  " Please don't use filereadable to test, as the new created file is also
  " unreadable before writting to disk.
  return &filetype == "c" || &filetype == "cpp"
endf
"}}}
"{{{ s:PDebug
" Use `:messages` to see debug info or read the var `b:clang_pdebug_storage`
" TODO: pretty print of info and write b:clang_pdebug_storage to new buffer,
" file, or someother places...
"
" Buffer var used to store messages
"   b:clang_pdebug_storage
"
" @head Prefix of debug info
" @info Can be a string list, string, or dict
" @lv   Debug level, write info only when lv < g:clang_debug, default is 1
func! s:PDebug(head, info, ...)
  let l:lv = a:0 > 0 && a:1 > 1 ? a:1 : 1

  if !exists('b:clang_pdebug_storage')
    let b:clang_pdebug_storage = []
  endif

  if l:lv <= g:clang_debug
    let l:msg = printf("Clang: debug: %s >>> %s", string(a:head), string(a:info))
    echom l:msg
    call add(b:clang_pdebug_storage, l:msg)
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
" {{{ s:BufVarSet
" Store current global var into b:clang_bufvars_storage
" Set global options that different in different buffer
func! s:BufVarSet()
  let b:clang_bufvars_storage= {
      \ 'completeopt':  &completeopt,
  \ }
  if &filetype == 'c' && !empty(g:clang_c_completeopt)
    exe 'set completeopt='.g:clang_c_completeopt
  elseif &filetype == 'cpp' && !empty(g:clang_cpp_completeopt)
    exe 'set completeopt='.g:clang_cpp_completeopt
  endif
endf
"}}}
" {{{ s:BufVarRestore
" Restore global vim options
func! s:BufVarRestore()
  if exists('b:clang_bufvars_storage')
    exe 'set completeopt='.b:clang_bufvars_storage['completeopt']
  endif
endf
" }}}
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
  let l:echo = g:clang_sh_is_cmd ? 'type NUL' : 'echo'
  let l:command = printf('%s | %s -fsyntax-only -v %s - 2>&1', l:echo, a:clang, a:options)
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
"{{{ s:DiscoverDefaultIncludeDirs
" Discover default include directories of clang and gcc (if existed).
" @options Additional options passed to clang and gcc, e.g. -stdlib=libc++
" @return List of dirs: ['path1', 'path2', ...]
func! s:DiscoverDefaultIncludeDirs(options)
  if g:clang_include_sysheaders_from_gcc
    let l:res = s:DiscoverIncludeDirs(g:clang_gcc_exec, a:options)
  else
    let l:res = s:DiscoverIncludeDirs(g:clang_exec, a:options)
  endif
  call s:PDebug("s:DiscoverDefaultIncludeDirs", l:res, 2)
  return l:res
endfunc
"}}}
"{{{ s:DiagnosticsWindowOpen
" Split a window to show clang diagnostics. If there's no diagnostics, close
" the split window.
" Global variable:
"   g:clang_diagsopt
"   g:clang_statusline
" Tab variable
"   t:clang_diags_bufnr         <= diagnostics window bufnr
"   t:clang_diags_driver_bufnr  <= the driver buffer number, who opens this window
"   NOTE: Don't use winnr, winnr maybe changed.
" @src Relative path to current source file, to replace <stdin>
" @diags A list of lines from clang diagnostics, or a diagnostics file name.
" @return -1 or buffer number t:clang_diags_bufnr
func! s:DiagnosticsWindowOpen(src, diags)
  if g:clang_diagsopt ==# ''
    return
  endif

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

  let l:cbuf = bufnr('%')
  " Here uses t:clang_diags_bufnr to keep only one window in a *tab*
  if !exists('t:clang_diags_bufnr') || !bufexists(t:clang_diags_bufnr)
    let t:clang_diags_bufnr = bufnr('ClangDiagnostics@' . l:cbuf, 1)
  endif

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
    call s:DiagnosticsWindowClose()
    return -1
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
    " 1. ^<stdin>:
    " 2. ^In file inlcuded from <stdin>:
    " So only to replace <stdin>: ?
    call append(line('$')-1, substitute(l:line, '<stdin>:', a:src . ':', ''))
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
""{{{ s:DiagnosticsWindowClose
" Close diagnostics window or quit the editor
" Tab variable
"   t:clang_diags_bufnr
func! s:DiagnosticsWindowClose()
  " diag window buffer is not exist
  if !exists('t:clang_diags_bufnr')
    return
  endif
  call s:PDebug("s:DiagnosticsWindowClose", "try")

  let l:cbn = bufnr('%')
  let l:cwn = bufwinnr(l:cbn)
  let l:dwn = bufwinnr(t:clang_diags_bufnr)

  " the window is not exist
  if l:dwn == -1
    return
  endif

  exe l:dwn . 'wincmd w'
  quit
  exe l:cwn . 'wincmd w'

  call s:PDebug("s:DiagnosticsWindowClose", l:dwn)
endf
"}}}
"{{{ s:DiagnosticsPreviewWindowClose
func! s:DiagnosticsPreviewWindowClose()
  call s:PDebug("s:DiagnosticsPreviewWindowClose", "")
  pclose
  call s:DiagnosticsWindowClose()
endf
"}}}
"{{{ s:DiagnosticsPreviewWindowCloseWhenLeave
" Called when driver buffer is unavailable, close preivew and window when
" leave from the driver buffer
func! s:DiagnosticsPreviewWindowCloseWhenLeave()
  if !exists('t:clang_diags_driver_bufnr')
    return
  endif

  let l:cbuf = expand('<abuf>')
  if l:cbuf != t:clang_diags_driver_bufnr
    return
  endif
  call s:DiagnosticsPreviewWindowClose()
endf
"}}}
"{{{  s:GenPCH
" Generate clang precompiled header.
" A new file with postfix '.pch' will be created if success.
" Note: There's no need to generate PCH files for C headers, as they can be
" parsed very fast! So only big C++ headers are recommended to be pre-compiled.
"
" @clang   Path of clang
" @header  Path of header to generate
" @return  Output of clang
"
" Use of global var:
"    b:clang_options_noPCH
"
func! s:GenPCH(clang, header)
  if ! s:IsValidFile()
    return
  endif

  " may want to re-read .clang, force init to update b:clang_options_noPCH
  call s:ClangCompleteInit(1)

  if a:header !~? '.h'
    let cho = confirm('Not a C/C++ header: ' . a:header . "\n" .
          \ 'Continue to generate PCH file ?',
          \ "&Yes\n&No", 2)
    if cho != 1 | return | endif
  endif

  let l:header      = shellescape(expand(a:header))
  let l:header_pch  = l:header . ".pch"
  let l:command = printf('%s -cc1 %s -emit-pch -o %s %s', a:clang, b:clang_options_noPCH, l:header_pch, l:header)
  call s:PDebug("s:GenPCH::cmd", l:command, 2)
  let l:clang_output = system(l:command)

  if v:shell_error
    " uses internal diag window to show errors
    call s:DiagnosticsWindowOpen(expand('%:p:.'), split(l:clang_output, '\n'))
    call s:PDebug("s:GenPCH", {'exit': v:shell_error, 'cmd': l:command, 'out': l:clang_output }, 3)
  else
    " may want to discover pch
    call s:ClangCompleteInit(1)
    " close the error window
    call s:DiagnosticsWindowClose()
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
  \ }
  if !empty(g:clang_sh_exec)
    exe 'set shell='.g:clang_sh_exec
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
endf
" }}}
" {{{ s:HasPreviewAbove
" Detect above view is preview window or not.
func! s:HasPreviewAbove()
  let l:cwin = winnr()
  let l:has = 0
  " goto above
  wincmd k
  if &completeopt =~ 'preview' && &previewwindow
    let l:has = 1
  endif
  exe l:cwin . 'wincmd w'
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

    if g:clang_verbose_pmenu
      " Keep `#` for further use
      "let l:proto = substitute(l:proto, '\(<#\)\|\(#>\)\|#', '', 'g')
      " Identify the type (test)
      if empty(l:res) || l:res[-1]['word'] !=# l:word
        if l:proto =~ '\v^\[#.{-}#\].+\(.*\).*' 
          let l:kind = 'f'
        elseif l:proto =~ '\v^\[#.*#\].+'
          let l:kind = 'v'
        elseif l:proto =~ '\v.+'
          let l:kind = 't'
        else
          let l:kind = '?'
        endif
        if l:kind == 'f' || l:kind == 'v'
          " Get the type of return value in the first []
          let l:typeraw = matchlist(l:proto, '\v^\[#.{-}#\]')
          let l:rettype = len(l:typeraw) ? typeraw[0][1:-2] : ""
          let l:core = l:proto[strlen(l:rettype) + 2 :]
        else
          let l:rettype = ""
          let l:core = l:proto
        endif
        " Remove # here
        let l:core = substitute(l:core, '\v\<#|#\>|#', '', 'g')
        let l:proto = substitute(l:proto, '\v\<#|#\>|#', '', 'g')
        let l:rettype = substitute(l:rettype, '\v\<#|#\>|#', '', 'g')
        " Another improvement: keep space for type, but only display abbr when
        " space is limited
        if strlen(l:core) > (&columns - wincol() - 25) && (&columns - wincol() > 20)
          let l:core = l:core[0:&columns - wincol() - 25] . "..."
        endif
        call add(l:res, {
              \ 'word': l:word,
              \ 'abbr' : l:core,
              \ 'kind' : l:kind,
              \ 'menu': l:rettype,
              \ 'info': l:proto,
              \ 'dup' : 1 })
      elseif !empty(l:res)
        " overload functions, for C++
        let l:proto = substitute(l:proto, '\v\<#|#\>|#', '', 'g')
        let l:res[-1]['info'] .= "\n" . l:proto
      endif
    else
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
    endif
  endfor

  return l:res
endf
" }}}
"{{{ s:SetNeomakeMakerArguments
" Set neomake_{c,cpp}_{clang,gcc}_maker variables to add the Clang arguments
" parsed from the .clang or .clang.ow files.
" @clang_options the options to be passed to makers
" @clang_root the directory whence the maker must be executed
func! s:SetNeomakeMakerArguments(clang_options, clang_root)
  " Split the arguments into a list
  " TODO: more intelligent splitting (an argument like '-I "/dir with/spaces"'
  "       would not work)
  let l:clang_options = split(a:clang_options, " ")

  if &filetype == 'cpp'

    " Store the original clang maker config to avoid a never-ending list of
    " args
    if !exists('s:origin_neomake_cpp_clang_maker')
      if !exists('g:neomake_cpp_clang_maker')
        try
          " Neomake default
          let s:origin_neomake_cpp_clang_maker = neomake#makers#ft#cpp#clang()
        catch /^Vim\%((\a\+)\)\=:E117/
          let s:origin_neomake_cpp_clang_maker = { "args" : [] }
        endtry
      else
        " User config
        let s:origin_neomake_cpp_clang_maker = g:neomake_cpp_clang_maker
        if !exists('s:origin_neomake_cpp_clang_maker["args"]')
          let s:origin_neomake_cpp_clang_maker["args"] = []
        endif
      endif
    endif

    " deepcopy needed as changing one would change the other otherwise.
    let g:neomake_cpp_clang_maker = deepcopy(s:origin_neomake_cpp_clang_maker)
    call extend(g:neomake_cpp_clang_maker["args"], l:clang_options)
    let g:neomake_cpp_clang_maker["cwd"] = a:clang_root

    " Store the original gcc maker config to avoid a never-ending list of
    " args
    if !exists('s:origin_neomake_cpp_gcc_maker')
      if !exists('g:neomake_cpp_gcc_maker')
        try
          " Neomake default
          let s:origin_neomake_cpp_gcc_maker = neomake#makers#ft#cpp#gcc()
        catch /^Vim\%((\a\+)\)\=:E117/
          let s:origin_neomake_cpp_gcc_maker = { "args" : [] }
        endtry
      else
        " User config
        let s:origin_neomake_cpp_gcc_maker = g:neomake_cpp_gcc_maker
        if !exists('s:origin_neomake_cpp_gcc_maker["args"]')
          let s:origin_neomake_cpp_gcc_maker["args"] = []
        endif
      endif
    endif

    " deepcopy needed as changing one would change the other otherwise.
    let g:neomake_cpp_gcc_maker = deepcopy(s:origin_neomake_cpp_gcc_maker)
    call extend(g:neomake_cpp_gcc_maker["args"], l:clang_options)
    let g:neomake_cpp_gcc_maker["args"] = l:clang_options
    let g:neomake_cpp_gcc_maker["cwd"] = a:clang_root

  elseif &filetype == 'c'

    " Store the original clang maker config to avoid a never-ending list of
    " args
    if !exists('s:origin_neomake_c_clang_maker')
      if !exists('g:neomake_c_clang_maker')
        try
          " Neomake default
          let s:origin_neomake_c_clang_maker = neomake#makers#ft#c#clang()
        catch /^Vim\%((\a\+)\)\=:E117/
          let s:origin_neomake_c_clang_maker = { "args" : [] }
        endtry
      else
        " User config
        let s:origin_neomake_c_clang_maker = g:neomake_c_clang_maker
        if !exists('s:origin_neomake_c_clang_maker["args"]')
          let s:origin_neomake_c_clang_maker["args"] = []
        endif
      endif
    endif

    " deepcopy needed as changing one would change the other otherwise.
    let g:neomake_c_clang_maker = deepcopy(s:origin_neomake_c_clang_maker)
    call extend(g:neomake_c_clang_maker["args"], l:clang_options)
    let g:neomake_c_clang_maker["cwd"] = a:clang_root

    " Store the original gcc maker config to avoid a never-ending list of
    " args
    if !exists('s:origin_neomake_c_gcc_maker')
      if !exists('g:neomake_c_gcc_maker')
        try
          " Neomake default
          let s:origin_neomake_c_gcc_maker = neomake#makers#ft#c#gcc()
        catch /^Vim\%((\a\+)\)\=:E117/
          let s:origin_neomake_c_gcc_maker = { "args" : [] }
        endtry
      else
        " User config
        let s:origin_neomake_c_gcc_maker = g:neomake_c_gcc_maker
        if !exists('s:origin_neomake_c_gcc_maker["args"]')
          let s:origin_neomake_c_gcc_maker["args"] = []
        endif
      endif
    endif

    " deepcopy needed as changing one would change the other otherwise.
    let g:neomake_c_gcc_maker = deepcopy(s:origin_neomake_c_gcc_maker)
    call extend(g:neomake_c_gcc_maker["args"], l:clang_options)
    let g:neomake_c_gcc_maker["args"] = l:clang_options
    let g:neomake_c_gcc_maker["cwd"] = a:clang_root

  endif
endf
"}}}
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
  let l:cwin = winnr()
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
  exe l:cwin . 'wincmd w'
endf
"}}}
"{{{ s:ClangCompleteDatabase
" Parse compile_commands.json
func! s:ClangCompleteDatabase()
  let l:clang_options = ''

  if g:clang_compilation_database !=# ''
    let l:ccd = fnameescape(fnamemodify(
          \ g:clang_compilation_database . '/compile_commands.json', '%:p'))
    let b:clang_root = fnameescape(fnamemodify(
          \ g:clang_compilation_database, ':p:h'))

    call s:PDebug("s:ClangCompleteInit::database", l:ccd)
    if filereadable(l:ccd)
      execute s:py . ' ' . s:compilation_database_py
    endif
  endif

  return l:clang_options
endfunction
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
"
" @force Force init
func! s:ClangCompleteInit(force)
  if ! s:IsValidFile()
    return
  endif

  " find project file first
  let l:cwd = fnameescape(getcwd())
  let l:fwd = fnameescape(expand('%:p:h'))
  silent exe 'lcd ' . l:fwd
  let l:dotclang    = findfile(g:clang_dotfile, '.;')
  let l:dotclangow  = findfile(g:clang_dotfile_overwrite, '.;')
  silent exe 'lcd '.l:cwd

  let l:has_dotclang = strlen(l:dotclang) + strlen(l:dotclangow)
  if !l:has_dotclang && g:clang_load_if_clang_dotfile
    return
  end

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

  " Firstly, add clang options for current buffer file
  let b:clang_options = s:ClangCompleteDatabase()

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
      if l:opt =~ "^[ \t]*//"
        continue
      endif
      let b:clang_options .= ' ' . l:opt
    endfor
  else
    " or means source file directory
    let b:clang_root = l:fwd
  endif

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

  " add current dir to include path
  let b:clang_options .= ' -I ' . shellescape(expand("%:p:h"))

  " add include directories if is enabled and not ow
  let l:default_incs = s:DiscoverDefaultIncludeDirs(b:clang_options)
  if g:clang_include_sysheaders && ! l:is_ow
    for l:dir in l:default_incs
      let b:clang_options .= ' -I ' . shellescape(l:dir)
    endfor
  endif

  " parse include path from &path
  if g:clang_use_path
    let l:dirs = map(split(&path, '\\\@<![, ]'), 'substitute(v:val, ''\\\([, ]\)'', ''\1'', ''g'')')
    for l:dir in l:dirs
      if len(l:dir) == 0 || !isdirectory(l:dir)
        continue
      endif

      " Add only absolute paths
      if matchstr(l:dir, '\s*/') != ''
        let b:clang_options .= ' -I ' . shellescape(l:dir)
      endif
    endfor
  endif

  " backup options without PCH support
  let b:clang_options_noPCH = b:clang_options
  " try to find PCH files in clang_root and clang_root/include
  " Or add `-include-pch /path/to/x.h.pch` into the root file .clang manully
  if &filetype == 'cpp' && b:clang_options !~# '-include-pch'
    let l:cwd = fnameescape(getcwd())
    silent exe 'lcd ' . b:clang_root
    let l:afx = findfile(g:clang_stdafx_h, '.;./include') . '.pch'
    if filereadable(l:afx)
      let b:clang_options .= ' -include-pch ' . shellescape(l:afx)
    endif
    silent exe 'lcd '.l:cwd
  endif

  " Create GenPCH command
  com! -nargs=* ClangGenPCHFromFile call <SID>GenPCH(g:clang_exec, <f-args>)

  " Create close diag and preview window command
  com! ClangCloseWindow  call <SID>DiagnosticsPreviewWindowClose()

  " Useful to re-initialize plugin if .clang is changed
  com! ClangCompleteInit call <SID>ClangCompleteInit(1)

  " Useful to check syntax only
  com! ClangSyntaxCheck call <SID>ClangSyntaxCheck(b:clang_root, b:clang_options)

  if g:clang_enable_format_command
    " Useful to format source code
    com! ClangFormat call <SID>ClangFormat()
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

  au BufUnload <buffer> call <SID>DiagnosticsPreviewWindowCloseWhenLeave()

  au BufEnter <buffer> call <SID>BufVarSet()
  au BufLeave <buffer> call <SID>BufVarRestore()

  " auto check syntax when write buffer
	if g:clang_check_syntax_auto
		au BufWritePost <buffer> ClangSyntaxCheck
	endif

  " auto format current file if is enabled
  if g:clang_format_auto
    au BufWritePost <buffer> ClangFormat
  endif

  if exists(":Neomake")
    " Set the configuration variables for Neomake makers
    call s:SetNeomakeMakerArguments(b:clang_options, b:clang_root)
  endif

  call s:GlobalVarRestore(l:gvars)
endf
"}}}
"{{{ ClangExecuteNeoJobHandler
"Handles stdout/stderr/exit events, and stores the stdout/stderr received from the shells.
func! ClangExecuteNeoJobHandler(job_id, data, event)
  if index(['stdout', 'stderr'], a:event) >= 0
    " when a:data[-1] is empty, which means is a complete line, otherwise need to concat a:data[-1]
    if !empty(b:clang_state[a:event])
      if empty(b:clang_state[a:event][-1])
        " a complete line, just remove the last empty line
        call remove(b:clang_state[a:event], -1)
      else
        " need to concat to the last line in previous chunk
        let b:clang_state[a:event][-1] .= a:data[0]
        call remove(a:data, 0)
      endif
    endif
    let b:clang_state[a:event] += a:data
  elseif a:event == 'exit'
    for event in ['stdout', 'stderr']
      if !empty(b:clang_state[event]) && empty(b:clang_state[event][-1])
        call remove(b:clang_state[event], -1)
      endif
    endfor
    call s:ClangExecuteDoneTriggerCompletion()
  endif
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
"
"     b:clang_execute_neojob_id  // used to stop previous job
"
" @root Clang root, project directory
" @clang_options Options appended to clang binary image
" @line Line to complete
" @col Column to complete
" @return [completion, diagnostics]
func! s:ClangExecute(root, clang_options, line, col)
  let l:cwd = fnameescape(getcwd())
  silent exe 'lcd ' . a:root
  let l:src = join(getline(1, '$'), "\n") . "\n"
  " shorter version, without redirecting stdout and stderr
  let l:cmd = printf('%s -fsyntax-only -Xclang -code-completion-macros -Xclang -code-completion-at=-:%d:%d %s -',
                      \ g:clang_exec, a:line, a:col, a:clang_options)
  let l:tmps = [tempname(), tempname()]
  " longer version, redirect output to different files
  let l:command = l:cmd.' 1>'.l:tmps[0].' 2>'.l:tmps[1]
  let l:res = [[], []]
  if has("nvim")
    call s:PDebug("s:ClangExecute::cmd", l:cmd, 2)
    " try to force stop last job which doesn't exit.
    if exists('b:clang_execute_neojob_id')
      try
        call jobstop(b:clang_execute_neojob_id)
      catch
        " Ignore
      endtry
    endif

    let l:optc = g:clang_sh_is_cmd ? '/c' : '-c'
    let l:argv = [g:clang_sh_exec, l:optc, l:cmd]
    " FuncRef must start with cap var
    let l:Handler = function('ClangExecuteNeoJobHandler')
    let l:opts = {'on_stdout': l:Handler, 'on_stderr': l:Handler, 'on_exit': l:Handler}
    let l:jobid = jobstart(l:argv, l:opts)
    let b:clang_execute_neojob_id = l:jobid

    if l:jobid > 0
      call s:PDebug("s:ClangExecute::jobid", l:jobid, 2)
      call jobsend(l:jobid, l:src)
      call jobclose(l:jobid, 'stdin')
    else
      call s:PError("s:ClangExecute", "Invalid jobid >> ".
           \ (l:jobid < 0 ? "Invalid clang_sh_exec" : "Job table is full or invalid arguments"))
    endif
  elseif !exists('v:servername') || empty(v:servername)
    let b:clang_state['state'] = 'ready'
    call s:PDebug("s:ClangExecute::cmd", l:command, 2)
    call system(l:command, l:src)
    let l:res = s:DeleteAfterReadTmps(l:tmps)
    call s:PDebug("s:ClangExecute::stdout", l:res[0], 3)
    call s:PDebug("s:ClangExecute::stderr", l:res[1], 2)
  else
    " Please note that '--remote-expr' executes expressions in server, but
    " '--remote-send' only sends keys, which is same as type keys in server...
    " Here occurs a bug if uses '--remote-send', the 'col(".")' is not right.
    let l:keys = printf("ClangExecuteDone('%s','%s')", l:tmps[0], l:tmps[1])
    let l:vcmd = printf('%s -s --noplugin --servername %s --remote-expr %s',
          \ g:clang_vim_exec, shellescape(v:servername), shellescape(l:keys))
    if g:clang_sh_is_cmd
      let l:input = tempname()
      call writefile(split(l:src, "\n", 1), l:input)
      let l:input = shellescape(l:input)
      let l:acmd = printf('type %s | %s & del %s & %s', l:input, l:command, l:input, l:vcmd)
      silent exe "!start /min cmd /c ".l:acmd
      let l:acmd_output = ''
    else
      let l:acmd = printf('(%s;%s)&', l:command, l:vcmd)
      let l:acmd_output = system(l:acmd, l:src)
    endif
    call s:PDebug("s:ClangExecute::cmd", l:acmd, 2)
    if v:shell_error
      if !empty(l:acmd_output)
        call s:DiagnosticsWindowOpen('', split(l:acmd_output, '\n'))
      endif
      call s:PError('s:ClangExecute::acmd', 'execute async command failed')
    endif
  endif
  silent exe 'lcd ' . l:cwd
  let b:clang_state['stdout'] = l:res[0]
  let b:clang_state['stderr'] = l:res[1]
  return l:res
endf
"}}}
"{{{ ClangExecuteDone
" Called by vim-client when clang is returned in asynchronized mode.
"
" Buffer vars:
"     b:clang_state => {
"       'stdout':  // updated in async mode
"       'stderr':  // updated in async mode
"     }
func! ClangExecuteDone(tmp1, tmp2)
  let l:res = s:DeleteAfterReadTmps([a:tmp1, a:tmp2])
  let b:clang_state['stdout'] = l:res[0]
  let b:clang_state['stderr'] = l:res[1]
  call s:ClangExecuteDoneTriggerCompletion()
endf
"}}}
"{{{ s:ClangExecuteDoneTriggerCompletion
" Won't overwirte 'stdout' and 'stderr' in b:clang_state
"
" Buffer vars:
"     b:clang_state => {
"       'state' :  // updated to 'sync' in async mode
"     }
func! s:ClangExecuteDoneTriggerCompletion()
  let b:clang_state['state'] = 'sync'
  call s:PDebug("ClangExecuteDoneTriggerCompletion::stdout", b:clang_state['stdout'], 3)
  call s:PDebug("ClangExecuteDoneTriggerCompletion::stderr", b:clang_state['stderr'], 2)
  " As the default action of <C-x><C-o> causes a 'pattern not found'
  " when the result is empty, which break our input, that's really painful...
  if ! empty(b:clang_state['stdout']) && mode() == 'i'
    call feedkeys("\<C-x>\<C-o>", "t")
  else
    call ClangComplete(0, ClangComplete(1, 0))
  endif
endf
"}}}
"{{{ s:ClangSyntaxCheck
" Only do syntax check without completion, will open diags window when have
" problem. Now this function will block...
func! s:ClangSyntaxCheck(root, clang_options)
  let l:cwd = fnameescape(getcwd())
  silent exe 'lcd ' . a:root
  let l:src = join(getline(1, '$'), "\n")
  let l:command = printf('%s -fsyntax-only %s -', g:clang_exec, a:clang_options)
  call s:PDebug("ClangSyntaxCheck::command", l:command)
  let l:clang_output = system(l:command, l:src)
  call s:DiagnosticsWindowOpen(expand('%:p:.'), split(l:clang_output, '\n'))
  silent exe 'lcd ' . l:cwd
endf
" }}}
" {{{ s:ClangFormat
" Call clang-format to format source code
func! s:ClangFormat()
  let l:view = winsaveview()
  let l:command = printf("%s -style=\"%s\" ", g:clang_format_exec, g:clang_format_style)
  silent execute '%!'. l:command
  call winrestview(l:view)
endf
"}}}
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
  let l:gvars = s:GlobalVarSet()
  let l:res = s:ClangComplete(a:findstart, a:base)
  call s:GlobalVarRestore(l:gvars)
  return l:res
endf

func! s:ClangComplete(findstart, base)
  call s:PDebug("ClangComplete", "start")

  if a:findstart
    call s:PDebug("ClangComplete", "phase 1")
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
    " close preview window if empty or has no preview window above, may above
    " other windows...
    if empty(b:clang_cache['completions']) || !s:HasPreviewAbove()
      pclose
    endif
    " call to show diagnostics
    call s:DiagnosticsWindowOpen(expand('%:p:.'), b:clang_cache['diagnostics'])
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
endf
"}}}

" vim: set shiftwidth=2 softtabstop=2 tabstop=2 expandtab foldmethod=marker:
