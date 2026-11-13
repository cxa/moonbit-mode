# moonbit-mode

An Emacs major mode for MoonBit source (`.mbt`), interfaces (`.mbti`), and
`moon.mod` / `moon.pkg` / `moon.work` configuration files.

Provides tree-sitter highlighting, two-space indentation, definition navigation,
Imenu, syntax-aware comment and delimiter handling, project discovery,
compilation error navigation, and optional Eglot support through `moon lsp`.

## Requirements

- Emacs 29 or later with built-in tree-sitter support. Tested with Emacs 31.1.
- The official [MoonBit grammar](https://github.com/moonbitlang/tree-sitter-moonbit),
  tested at revision `5435c307c6cf2ef0d508a99047b06f35a4308444`.
- A tree-sitter runtime that accepts grammar ABI 15. The Lisp API target and
  grammar ABI are separate requirements; an older Emacs build's runtime may
  reject this parser. Use `M-x treesit-inspect-mode` to inspect parsed code.

Without a usable parser, the mode still opens and provides comment commands;
structural highlighting, indentation, navigation and Imenu require the parser.

## Install the grammar

For the latest grammar, configure Emacs and run
`M-x treesit-install-language-grammar RET moonbit`:

```elisp
(add-to-list 'treesit-language-source-alist
             '(moonbit "https://github.com/moonbitlang/tree-sitter-moonbit"
                       "main" "src"))
```

For the exact tested revision, build the checked-out generated parser with a C
compiler. This works on macOS and Linux and does not require the tree-sitter CLI:

```sh
git clone https://github.com/moonbitlang/tree-sitter-moonbit.git
cd tree-sitter-moonbit
git checkout 5435c307c6cf2ef0d508a99047b06f35a4308444
cc -O2 -fPIC -shared -Isrc src/parser.c src/scanner.c \
  -o libtree-sitter-moonbit.so
```

Copy `libtree-sitter-moonbit.so` into the `tree-sitter` subdirectory of your
`user-emacs-directory`, or add its directory to `treesit-extra-load-path`.
Restart Emacs after replacing an already loaded grammar. Do not pass a raw
commit SHA as the branch argument of Emacs 29's grammar installer; use the
checkout above to pin the revision.

## Install the mode

Clone this repository, then add it to your load path:

```elisp
(add-to-list 'load-path "/path/to/moonbit-mode")
(require 'moonbit-mode)
```

Or install it with Emacs's built-in VC package support:

```elisp
(package-vc-install "https://github.com/cxa/moonbit-mode")
```

Customize `moonbit-indent-offset` to change the default indentation:

```elisp
(setq moonbit-indent-offset 2)
```

`M-.` and other language services become available after connecting Eglot.
`M-x imenu`, `C-M-a` / `C-M-e`, and `M-;` provide the mode's symbol index,
definition navigation, and commenting.

Character literals, raw `#|` lines and interpolated `$|` lines have syntax
properties as well as highlighting. Comment markers and quotes in literal text
therefore do not confuse Emacs's comment commands or delimiter pairing. Code
inside `\{...}` retains code syntax. Indentation handles multiline signatures,
calls, match arms and chains, with a local fallback while closers or match arms
are still being typed.

## Projects and compilation

Once the mode is loaded, `project.el` recognizes `moon.mod` and legacy
`moon.mod.json` module roots from subpackages, including outside Git. A
`moon.work` root is used for its listed member modules; an unrelated ancestor
workspace does not capture a nested module. `MOON_WORK=off` disables workspace
selection, and an explicit `MOON_WORK` path selects that workspace. File search
respects Git ignores and omits `_build`, `target`, `.mooncakes`, and `.repos`.
Legacy root detection supports migration; it does not make old JSON manifests
valid with the current toolchain.

`C-c C-c` runs the standard `project-compile` command at that root, with
`moon build` as the default. Change `moonbit-compile-command`, enter another
command at the prompt, or set `compile-command` in directory-local variables
to use `moon check`, `moon test`, or a project-specific build. `M-x compile`
remains available for running a command from the current directory.

MoonBit's rendered diagnostics and `--no-render` locations are clickable in
standard compilation buffers. Use `M-g n` / `M-g p` (`next-error` /
`previous-error`) to visit their file, line and column. Warnings are identified
as warnings.

## Language server

The mode registers `("moon" "lsp")` with Eglot. Install a current MoonBit
[toolchain](https://www.moonbitlang.com/download/) and ensure its `bin` directory
is in both Emacs's `exec-path` and the `PATH` environment variable: `moon` finds
the `moon-lsp` subprocess through `PATH`. For the default installation:

```elisp
(let ((moon-bin (expand-file-name "~/.moon/bin")))
  (add-to-list 'exec-path moon-bin)
  (setenv "PATH" (concat moon-bin path-separator (getenv "PATH"))))
```

Run `M-x eglot` in a MoonBit buffer to connect. To opt into starting it
automatically:

```elisp
(add-hook 'moonbit-mode-hook #'eglot-ensure)
```

The mode itself does not start a server. The native server is the default in
[MoonBit v0.10.0 and later](https://www.moonbitlang.com/updates/2026/06/08/moonbit-0-10-0-release),
including support for `moon.mod` and `moon.pkg`.

Live Eglot integration was verified on 2026-11-13 with Emacs 31.1 on macOS ARM64,
`moon 0.1.20261104`, and `moonc` / `moon-lsp v0.10.20+65efd5b93`. Checks from a subpackage covered
hover, completion, cross-file definition lookup, type-error diagnostics and
their removal after correction, formatting, and configuration completions in
both `moon.mod` and `moon.pkg`.

## Compatibility notes

Alignment checked on 2026-11-13 against the
[MoonBit v0.10.19 release](https://www.moonbitlang.com/updates/2026/11/05/index)
and the grammar revision above. Highlighting includes `#derive` attributes,
`Int32` / `UInt32`, tuple structs, suberrors, extensible enum bodies/extensions,
list comprehensions, regex strings, and `#|` / `$|` multiline strings. Expressions
inside string interpolation keep their own highlighting.

The tested upstream grammar still lacks several v0.10.19 forms: byte regex
literals (`reb"..."`), standalone extensible enum declarations without a body,
`declare let`, and attribute arguments containing arrays or package references.
These can produce parse errors and affect structural editing around them.
Updating the mode alone cannot add parser support for those forms.

`.mbtx` scripts use frontmatter that this grammar does not yet recognize, so
those files are not associated automatically. `.mbtp` predicate files need a
separate grammar. Markdown (`.mbt.md`) and legacy JSON manifests retain their
existing modes.

## Tests

Run the regression suite on macOS or Linux with Emacs, Git and a C compiler:

```sh
sh test/run-tests.sh
```

The runner checks out and builds the exact grammar revision in a temporary
directory, checks byte compilation, runs a parser-free comment test in a separate
Emacs process, and runs ERT regressions for parsing, actual faces, indentation,
Imenu, navigation, file associations, syntax updates after edits, project roots,
compilation locations and warning severity, and opt-in Eglot registration. Parser tests
fail if the library cannot load; they do not silently skip.

To test with an already built grammar instead:

```sh
MOONBIT_TEST_GRAMMAR_DIR=/path/to/grammar-library-directory \
  emacs -Q --batch -L . -l test/moonbit-mode-test.el \
  -f ert-run-tests-batch-and-exit
```

With a current MoonBit toolchain (`moon` and `moon-lsp`) in `PATH`, run the
separate live toolchain regressions:

```sh
sh test/run-lsp-tests.sh
```

They create temporary modules, connect from a subpackage through the mode's
Eglot registration, and test the services listed above. A real failing build
also verifies `project-compile` and `next-error`, including paths with spaces.
The tests then stop their processes and remove their modules.
They also work without a tree-sitter parser. Set `MOONBIT_TEST_GRAMMAR_DIR` to
include one, or `MOONBIT_LSP_TEST_LOG_DIR` to retain the Eglot protocol log.
