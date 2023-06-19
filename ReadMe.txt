编译
==
    Mac:
        ```
        make
        ```

运行
==
    iOS:
        ```
        ./lua ps.lua 
        ./lua vmmap.lua --pid=xxx
        ./sysctl -h
        ./sysctl -A | ./filt kern
        ./kdv
        ```

credits
* kdv from newosxbook.com/tools/kdv.html
* Makefile from haxx

