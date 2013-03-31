Description
---------------
Use of clang to parse and complete C/C++ source files.

Why
---------------
I was a user of clang\_compelete and it's really a good job, but someday I found that
I must write another plugin to overcome some _drawbacks_ of it...

vim-clang VS [Rip-Rip/clang_complete][1]
---------------

1. User options can be set for different file types in vim-clang.
    
        let g:clang_c_options = '-std=gnu11'
        let g:clang_cpp_options = '-std=c++11 -stdlib=libc++'

2. vim-clang is faster than clang_compelte(not use libclang).
vim-clang does not support libclang now, and I don't think it's a good idea to use cindex.py(python binding for clang) directly.
If you use clang_complete with libclang and open many C/C++ source files, you'll find that VIM eats up **hundreds** of MB RAM...
    * vim-clang caches output of clang and reuses if the completion point is not changed and without errors.
    * vim-clang only runs clang once to get completions and diagnostics.

3. vim-clang is more friendly than clang_complete.
    * vim-clang uses the prview window to show prototypes for C/C++ sources.
      Generally, C++ source has many overload functions and most of completons are very complex,
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


Installation
-------------
Put the file `plugin/clang.vim` into `~/.vim/plugin`.


Options and Commands
--------------------
See file `plugin/clang.vim`


Windows support
--------------------
I don't know if some people would like to use VIM + Clang comppletion on Micorsot Windows,
as many good IDE(e.g. Virtual Studio, VC++ expres etc.) provide better experience.
Another reason is that Windows is not the first class platform supported by Clang.
But as the [ishani][2] provides standalone and prebuild Clang binary files,
which helps a lot on vim-clang support for Windows. Now you can [download][3] the latest prebuild
Clang for Windows from [here][3].


Screenshots
-------------

#### Complete C source
###### Start, popup completions and open preview window
![C source](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-142049_1278x776_scrot_zps2982ca2a.png)
###### Done, open diagnostics window
![C source done](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-142131_1278x774_scrot_zps7d9633c5.png)

#### Complete C++ source in another tabpage.
###### Start, popup completions and open preview window
![C++ source](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-142349_1276x774_scrot_zps95dfe9cb.png)
###### Done, open diagnostics window
![C++ source done](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-142402_1278x773_scrot_zps05796743.png)

#### Generate PCH
###### Start to generate PCH
![Generate PCH](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-142540_593x636_scrot_zpsd2510a71.png)
###### Generate PCH successfully
![Generate PCH successfully](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-142552_594x637_scrot_zps3d337ed2.png)

#### Usage of .clang
###### .clang is located in the project **root**
![.clang](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-143601_746x153_scrot_zpsb3b4e275.png)
###### Start, popup completions and open preview window
![.clang C source](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-143705_591x636_scrot_zpsac9083d6.png)
###### Done, open diagnostics window
![.clang C source done](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/2013-02-06-143716_593x635_scrot_zps260a9d03.png)


#### vim-clang on Microsoft Windows
![.clang](http://i1265.photobucket.com/albums/jj508/justmao945/vim-clang/65E068079898_zps573dcaae.png)


[1]: https://github.com/Rip-Rip/clang_complete
[2]: http://www.ishani.org
[3]: http://www.ishani.org/web/articles/code/clang-win32/
