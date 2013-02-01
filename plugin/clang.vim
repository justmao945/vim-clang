"{{{ Description
" Script Name: clang.vim
" Version:     1.0.0 (2013-xx-xx)
" Authors:     2010~2013 Xavier Deguillard <deguilx@gmail.com>
"              2013~     Jianjun Mao <justmao945@gmail.com>
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
"
"  - g:clang_dotfilet

"       Each project can have a dot file at his root, containing the compiler
"       options. This is useful if you're using some non-standard include paths.
"       Default: '.clang'
"
"  - g:clang_exec
"       Name or path of clang executable.
"       Note: Use this if clang has a non-standard name, or isn't in the path.
"       Default: 'clang'
"
" TODO
"   1. Private members filter
"   2. Super tab?
"   4. Append error to split window
"   5. Test cases
"   6. Ignore when <.> in comments and string and includes
"   7. PCH support, reduce a half of time to complete
"
" F__K:
"   1. libcxx is slow than g++ headers
"   2. result of STL is usually complex and hard to read...
"   3. PCH must be recompiled after change the _header_
"
" Refs:
"   [1] http://clang.llvm.org/docs/
"}}}


"{{{ Global initialization
if exists("g:clang_loaded")
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

" Init on c/c++ files
au FileType c,cpp call s:ClangCompleteInit()
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
" @lang Language supported by clang: c/cpp/xxx.
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


"{{{ s:ClangCompleteInit
" Initialization for this script:
"   1. find set root to file .clang
"   2. read config file .clang
"   3. append user options first
"   3.5 append clang default include directories to option
"   4. setup buffer maps to auto completion
"
func! s:ClangCompleteInit()
  let l:dotclang = findfile(g:clang_dotfile, '.;')

  " clang root(aka .clang located directory) for current buffer
  let b:clang_root = fnamemodify(l:dotclang, ":p:h")

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
  
  let l:incs = s:DiscoverIncludeDirs(g:clang_exec, b:clang_options)
  for l:dir in l:incs
    let b:clang_options .= ' -I' . l:dir
  endfor

  setlocal completefunc=ClangComplete
  setlocal omnifunc=ClangComplete

  " Auto completion
  inoremap <expr> <buffer> . <SID>CompleteDot()
  inoremap <expr> <buffer> > <SID>CompleteArrow()
  if &filetype == 'cpp'
    inoremap <expr> <buffer> : <SID>CompleteColon()
  endif
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


"{{{ ClangComplete
" Complete main routine, valid cases are showed as below.
" Note: This will not parse previous lines, which means that only care
"       current line.
"
" <IDENT> indicates an identifier
" </> the completion point
" <.> including a `.` or `->` or `::`
" <s> zero or more spaces and tabs
" <*> is anything other then the new line `\n`
"
" 1  <*><IDENT><s></>         complete identfiers start with <IDENT>
" 2  <*><IDENT><s><.><s></>   complete all members
" 3  <*><IDENT><s><.><s><IDENT><s></>  complete identifers start with <IDENT>
" 4  <s><.><s></>             same as 2
" 5  <s><.><s><IDENT><s></>   same as 3
"
" Completion output of clang:
"   COMPLETION: <ident> : <prototype>
"   0           12     c  c+3
"
" More about @findstart and @base to check :h omnifunc
" FIXME Tabs can't work corrently at ... =~ '\s' ?
" TODO Cross line completion ? Because C/C++ is not strict with ` ` and '\n'
func! ClangComplete(findstart, base)
  if a:findstart
    let l:line = getline('.')
    let l:start = col('.') - 1 " start column
    
    "trim right spaces
    while l:start > 0 && l:line[l:start - 1] =~ '\s'
      let l:start -= 1
    endwhile
    
    let l:col = l:start
    let b:compat = l:start + 1 " store current completion point
    while l:col > 0 && l:line[l:col - 1] =~# '[_0-9a-zA-Z]'  " find valid ident
      let l:col -= 1
    endwhile
    
    let b:base = ''  " base word to filter completions
    if l:col < l:start " may exist <IDENT>
      if l:line[l:col] =~# '[a-zA-Z]' "<ident> doesn't start with a number
        let b:base = l:line[l:col : l:start-1]
        let l:start = l:col " reset l:start in case 1
      else
        echo "Can't complete after an invalid identifier <"
            \. l:line[l:col : l:start-1] . ">"
        return -3
      endif
    endif
    
    " trim right spaces
    while l:col > 0 && l:line[l:col -1] =~ '\s'
      let l:col -= 1
    endwhile
   
    let l:ismber = 0
    if l:line[l:col - 1] == '.'
        \ || (l:line[l:col - 1] == '>' && l:line[l:col - 2] == '-')
        \ || (&filetype == 'cpp' && 
        \     l:line[l:col - 1] == ':' && l:line[l:col - 2] == ':')
      let l:start  = l:col
      let b:compat = l:col + 1
      let l:col -= 2
      let l:ismber = 1
    endif
    if l:line[l:col - 1] == '.'
      let l:col += 1
    endif
    
    if b:compat == 1
      "Nothing to complete, blank line completion is not supported..."
      return -3
    endif
    
    if ! l:ismber && b:base == ''
      "Noting to complete, pattern completion is not supported..."
      return -3
    endif
    " FIXME buggy when update in the second phase ?
    exe 'silent update'
    return l:start
  else
    exe "cd " . b:clang_root
    let l:command = g:clang_exec. ' -cc1 -fsyntax-only -code-completion-macros'
          \ .' -code-completion-at='.expand("%:t").':'.line('.').':' . b:compat
          \ .' ' . b:clang_options . ' ' . expand("%:p:.")
    let l:clang_output = split(system(l:command), "\n")
    let l:res = []
    " Completions always comes after errors and warnings
    let l:i = 0
    for l:line in l:clang_output
      if l:line =~# '^COMPLETION:' " parse completions
        break
      else " Write info to split window
        
        
        
      endif
      let l:i += 1
    endfor
    
    if l:i > 0
      let l:clang_output = l:clang_output[l:i : -1]
    endif
   
    for l:line in l:clang_output
      let l:s = stridx(l:line, ':', 13)
      let l:word  = l:line[12 : l:s-2]
      let l:proto = l:line[l:s+2 : -1]
      
      " only show overload functions named as b:base
      if (((!empty(l:res) && (l:res[-1]["word"] !=# l:word)) || empty(l:res))
          \  && l:word =~# '^' . b:base && l:word !~# '(Hidden)$')
        \ || b:base ==# l:word
        let l:proto = substitute(l:proto, '\(<#\)\|\(#>\)\|#', '', 'g')
        call add(l:res, {
            \ 'word': l:word,
            \ 'menu': l:proto,
            \ 'info': l:proto,
            \ 'dup' : 1 })
      endif
    endfor
    return l:res
  endif
endf
"}}}
