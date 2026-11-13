#!/bin/sh
# Requires a current installed MoonBit toolchain, including moon-lsp.
set -eu
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
"${EMACS:-emacs}" -Q --batch -L "$repo_dir" \
  -l "$repo_dir/test/moonbit-lsp-test.el" \
  -l "$repo_dir/test/moonbit-toolchain-test.el" -f ert-run-tests-batch-and-exit
