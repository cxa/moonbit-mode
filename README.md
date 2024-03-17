# moonbit-mode

> [!WARNING]  
> Still in early stage development, use with caution

## Prerequisites

- Emacs 29 with Tree-sitter support
- Build MoonBit grammars for Emacs:
    ``` shell
    git clone git@github.com:moonbitlang/tree-sitter-moonbit.git
    cd tree-sitter-moonbit/src
    cc -fPIC -c -I. parser.c
    cc -fPIC -c -I. scanner.c
    cc -fPIC -shared *.o -o libtree-sitter-moonbit.so
    mv libtree-sitter-moonbit.so ~/.emacs.d/tree-sitter/
    ```

## Install

You can either:

- Clone this repo, add the `moonbit-mode.el` file to your Emacs `load-path`: `(add-to-list 'load-path "/path/to/moonbit-mode")`
- With `use-package`:
    ``` elsip
    (use-package moonbit-mode
        :quelpa (moonbit-mode :fetcher github :repo "cxa/moonbit-mode"))
    ```

