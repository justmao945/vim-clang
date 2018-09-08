vim-clang
---------------

[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/justmao945/vim-clang?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)


Use of clang to parse and complete C/C++ source files.


![C source](http://justmao945.github.io/static/vim-clang/2014-01-12-async.gif)


Installation
-------------
* Require executable `clang` installed.
* Putting the content of `plugin/` into `~/.vim/plugin` works.
* Using a [plugin manager][8], like [pathogen.vim][4], is recommended.
  Installation via pathogen is done by
  `cd ~/.vim/bundle; git clone https://github.com/justmao945/vim-clang.git`.


Why
---------------
I was a user of clang\_complete and it's really a good job, but someday I found that
I must write another plugin to overcome some _drawbacks_ of it.

### vim-clang VS [Rip-Rip/clang_complete][1]


1. User options can be set for different file types in vim-clang.
    
        let g:clang_c_options = '-std=gnu11'
        let g:clang_cpp_options = '-std=c++11 -stdlib=libc++'

2. vim-clang is faster than clang_complete (not using libclang).
vim-clang does not support libclang now, and I don't think it's a good idea to use cindex.py(python binding for clang) directly.
If you use clang_complete with libclang and open many C/C++ source files, you'll find that VIM eats up **hundreds** of MB RAM...
    * vim-clang caches output of clang and reuses if the completion point is not changed and without errors.
    * vim-clang only runs clang once to get completions and diagnostics.

3. vim-clang is more friendly than clang_complete.
    * vim-clang uses the preview window to show prototypes for C/C++ sources.
      Generally, C++ source has many overload functions and most of completions are very complex,
      which is not good to put this into OmniComplete popup menu.
    * vim-clang uses a split window to show the caret diagnostics from clang.
      clang_complete uses quickfix window to show diagnostics without caret, but that's not the best choice...
      Because the caret diagnostics of clang including many useful infomation.

4. vim-clang supports relative include path in .clang configuration file.
    
        proj/
        |-- .clang
        |-- include/
            |-- main.h
        |-- src/
            |-- main.c
        |-- test/
            |-- main_test.c
        
        $ cat .clang
        -I.

5. Better PCH support. vim-clang will find stdafx.h.pch automatically.

### vim-clang VS [Valloric/YouCompleteMe][5]
[YouCompleteMe][5] is more powerful than vim-clang, that has a well designed client-server
architecture to deal the memory problem in clang_complete.


Features
--------

### Asynchronized mode [new]
* Now vim-clang supports to call clang executable asynchronously that it won't block
vim during the completion. This is very useful if your project is large and the machine
is not very powerful to parse them in tens of milliseconds. In synchronized mode you'll
find that's too 'slow' to wait the completion...

* This mode is implemented by starting another vim process to notify the finish of the
   completion, so `+clientserver` option is required to compile the vim(generally added).

* GVIM is required to use this mode, seems given `--servername ???` to `vim` is not working.

* Job control is used to run clang when in neovim, which is really very nice! Thank you 
  [syswow][6].

### Compile commands [new]
* Use `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=1` to generate `compile_commands.json`

* To use the compile commands database in vim-clang, set the `g:clang_compilation_database`
variable in your vimrc to your cmake build path.

        let g:clang_compilation_database = './build'

### Neomake integration [new]
* vim-clang now adds the compilation arguments parsed from .clang and .clang.ow
  to Neomake configuration variables. This means that the include search paths
  (`-I`) that are in the .clang files will be passed down to the clang and gcc
  makers from Neomake without overriding your configuration.
* vim-clang will also set the directory from where the maker will run, which is
  the directory where the first .clang or .clang.ow is.

The variables that are affected are:
* `g:neomake_cpp_clang_maker`
* `g:neomake_cpp_gcc_maker`
* `g:neomake_c_clang_maker`
* `g:neomake_c_gcc_maker`

Options and Commands
--------------------
`:h clang.txt`

OS requirement
--------------------
Tested on
* Ubuntu 14.04
* Mac OS X 10.10
* Windows 7

[1]: https://github.com/Rip-Rip/clang_complete
[2]: http://www.ishani.org
[3]: http://www.ishani.org/web/articles/code/clang-win32/
[4]: https://github.com/tpope/vim-pathogen
[5]: https://github.com/Valloric/YouCompleteMe
[6]: https://github.com/syswow
[7]: https://github.com/Shougo/neocomplete
[8]: https://vi.stackexchange.com/questions/388/what-is-the-difference-between-the-vim-plugin-managers
