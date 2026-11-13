;;; moonbit-mode.el --- Major mode for editing MoonBit -*- lexical-binding:t -*-

;; Copyright (C) 2024-present CHEN Xian'an (a.k.a `realazy').

;; Maintainer: xianan.chen@gmail.com
;; Version: 0.2.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages
;; URL: https://github.com/cxa/moonbit-mode

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides major modes for MoonBit.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'project)
(require 'treesit)

(defgroup moonbit nil
  "Customization variables for MoonBit mode."
  :tag "MoonBit"
  :group 'languages)

(defcustom moonbit-indent-offset 2
  "Number of spaces per indentation level in MoonBit buffers."
  :type 'natnum
  :safe #'natnump
  :group 'moonbit)

(defcustom moonbit-compile-command "moon build"
  "Default compilation command for MoonBit buffers.
A directory-local `compile-command' can override this per project."
  :type 'string
  :group 'moonbit)

(defconst moonbit--module-files '("moon.mod" "moon.mod.json")
  "Files that mark a MoonBit module root.")

(defvar moonbit-mode-syntax-table)

(defun moonbit--workspace-members (file)
  "Read member paths from workspace FILE without evaluating its contents.
Return nil for an unreadable or malformed manifest."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (set-syntax-table moonbit-mode-syntax-table)
        (goto-char (point-min))
        (catch 'members
          (while (re-search-forward "\\_<members\\_>\\s-*=" nil t)
            (unless (save-excursion (nth 8 (syntax-ppss (match-beginning 0))))
              (forward-comment (point-max))
              (unless (eq (char-after) ?\[) (throw 'members nil))
              (forward-char)
              (let (members done)
                (while (not done)
                  (forward-comment (point-max))
                  (pcase (char-after)
                    (?\] (setq done t))
                    (?\" (push (json-read) members)
                         (forward-comment (point-max))
                         (pcase (char-after)
                           (?, (forward-char))
                           (?\] (setq done t))
                           (_ (throw 'members nil))))
                    (_ (throw 'members nil))))
                (throw 'members (nreverse members)))))))
    (error nil)))

(defun moonbit--project-root (directory)
  "Find the MoonBit module or participating workspace above DIRECTORY."
  (let* ((module (locate-dominating-file
                  directory
                  (lambda (dir)
                    (cl-some (lambda (file) (file-regular-p (expand-file-name file dir)))
                             moonbit--module-files))))
         (setting (getenv "MOON_WORK"))
         (local-workspace
          (locate-dominating-file
           directory (lambda (dir) (file-regular-p (expand-file-name "moon.work" dir)))))
         (workspace
          (cond
           ((or (equal setting "off")
                (and (null setting) (getenv "MOON_NO_WORKSPACE"))) nil)
           ((and setting (not (member setting '("" "auto"))))
            (let ((file (expand-file-name setting directory)))
              (when (file-regular-p file) (file-name-directory file))))
           (t local-workspace))))
    (cond
     ;; A Moon-specific override must not capture unrelated language projects.
     ((and (null module) (null local-workspace)) nil)
     ((null workspace) module)
     ;; An explicit override or a workspace encountered before a module wins.
     ((or (and setting (not (member setting '("" "auto" "off"))))
          (null module)
          (equal (file-truename module) (file-truename workspace))
          (file-in-directory-p workspace module))
      workspace)
     ((cl-some
       (lambda (member)
         (equal (file-truename (file-name-as-directory (expand-file-name member workspace)))
                (file-truename module)))
       (moonbit--workspace-members (expand-file-name "moon.work" workspace)))
      workspace)
     (t module))))

(defun moonbit-project-find (directory)
  "Return a MoonBit project containing DIRECTORY, or nil."
  (when-let* ((root (moonbit--project-root directory)))
    (cons 'moonbit (file-name-as-directory (expand-file-name root)))))

(cl-defmethod project-root ((project (head moonbit)))
  (cdr project))

(cl-defmethod project-ignores ((project (head moonbit)) directory)
  (append '("_build/" "target/" ".mooncakes/" ".repos/")
          (when-let* ((vc (project-try-vc (project-root project))))
            (project-ignores vc (or directory (project-root project))))
          (cl-call-next-method)))

(add-hook 'project-find-functions #'moonbit-project-find)

(defvar compilation-error-regexp-alist)
(defvar compilation-error-regexp-alist-alist)

(with-eval-after-load 'compile
  (dolist
      (entry
       '((moonbit-rendered
          "^\\(?:\\(Warning\\)\\|Error\\):[^\n]*\n[ \t]*╭─\\[ \\(.+\\):\\([0-9]+\\):\\([0-9]+\\) \\]"
          2 3 4 (1))
         (moonbit-raw
          "^\\(.+\\):\\([0-9]+\\):\\([0-9]+\\)-[0-9]+:[0-9]+ \\[\\(?:E\\|\\(W\\)\\)[0-9]+\\]"
          1 2 3 (4))))
    (add-to-list 'compilation-error-regexp-alist-alist entry)
    (add-to-list 'compilation-error-regexp-alist (car entry))))

(defvar moonbit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'project-compile)
    map)
  "Keymap for `moonbit-mode'.")

(defface moonbit-alt-type-face
  '((t . (:inherit font-lock-preprocessor-face)))
  "Face for constructors, distinguished from type names."
  :group 'moonbit)

(defvar moonbit-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_ "w" table)
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23" table)
    (modify-syntax-entry ?\n "> b" table)
    table)
  "Syntax table for `moonbit-mode'.")

(defvar moonbit--keywords
  '("if" "else" "while" "for" "in" "loop" "break" "continue" "return"
    "match" "guard" "is" "as" "try" "catch" "raise" "noraise" "nobreak"
    "fn" "test" "let" "letrec" "mut" "const" "and" "defer" "async"
    "type" "struct" "enum" "extenum" "trait" "suberror" "typealias"
    "traitalias" "fnalias" "pub" "priv" "readonly" "all" "open" "extern"
    "declare" "derive" "impl" "with" "extend" "where" "using" "package"
    "import" "lexmatch" "lexmatch?" "lexscan" "longest" "not"
    "proof_assert" "proof_let")
  "Keywords recognized by the MoonBit grammar.")

(defvar moonbit--operators
  '("|>" "<|" "<+" "<?" "*" "/" "%" "+" "-" ">>" "<<" "|" "&" "^"
    ">" ">=" "<=" "<" "==" "!=" "&&" "||" "=" "+=" "-=" "*=" "/=" "%="
    "!" "!!" "?" "->" "=>" "=~" "..<" "..=" "..<=" "..>" "..>=" ">.." ">=..")
  "Operators recognized by the MoonBit grammar.")

(defun moonbit--fontify-multiline-content (node override start end &rest _)
  "Fontify NODE as string text unless it contains an interpolator.
OVERRIDE, START and END are supplied by tree-sitter font-lock."
  (unless (treesit-node-child node 0 t)
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     'font-lock-string-face override start end)))

(defvar moonbit--font-lock-rules
  `(:language moonbit :feature comment
    ([(comment) (block_comment)] @font-lock-comment-face)

    :language moonbit :feature literal
    ((boolean_literal) @font-lock-constant-face
     [(integer_literal) (double_literal) (float_literal)] @font-lock-number-face
     [(char_literal) (byte_literal) (byte_escape_literal)] @font-lock-string-face)

    :language moonbit :feature string
    ([(string_literal) (bytes_literal) (regex_literal)
      (string_fragment) (multiline_string_content)] @font-lock-string-face
     (string_interpolation "\"" @font-lock-string-face)
     (multiline_string_fragment "#|" @font-lock-comment-face)
     (multiline_interpolation_fragment "$|" @font-lock-comment-face)
     (multiline_interpolation_content) @moonbit--fontify-multiline-content
     (interpolator
      "\\{" @font-lock-misc-punctuation-face
      "}" @font-lock-misc-punctuation-face))

    :language moonbit :feature keyword
    ([,@moonbit--keywords] @font-lock-keyword-face)

    :language moonbit :feature attribute
    ((attribute "#" @font-lock-preprocessor-face
                (attribute_expression
                 (lowercase_identifier) @font-lock-preprocessor-face)))

    :language moonbit :feature bracket
    (["(" ")" "[" "]" "{" "}"] @font-lock-bracket-face)

    :language moonbit :feature delimiter
    (["." ":" "::" "," ";" ".."] @font-lock-delimiter-face)

    :language moonbit :feature operator
    ([,@moonbit--operators] @font-lock-operator-face)

    :language moonbit :feature identifier
    ((lowercase_identifier) @font-lock-variable-name-face
     (dot_lowercase_identifier) @font-lock-variable-use-face
     (package_statement_identifier) @font-lock-variable-name-face
     (package_identifier) @font-lock-constant-face
     [(uppercase_identifier) (dot_uppercase_identifier)] @font-lock-type-face)

    :language moonbit :feature definition :override t
    ((function_identifier
      (lowercase_identifier) @font-lock-function-name-face)
     (function_definition
      (function_identifier (uppercase_identifier) @font-lock-function-name-face))
     (named_lambda_expression (lowercase_identifier) @font-lock-function-name-face)
     (value_definition (lowercase_identifier) @font-lock-constant-face)
     (const_definition (uppercase_identifier) @font-lock-constant-face)
     (enum_constructor (uppercase_identifier) @moonbit-alt-type-face)
     (constructor_expression
      [(uppercase_identifier) (dot_uppercase_identifier)] @moonbit-alt-type-face))

    :language moonbit :feature function :override t
    ((apply_expression
      (qualified_identifier
       [(lowercase_identifier) (dot_lowercase_identifier)] @font-lock-function-call-face))
     (dot_apply_expression (dot_identifier) @font-lock-function-call-face)
     (dot_dot_apply_expression (dot_dot_identifier) @font-lock-function-call-face)
     (method_expression (lowercase_identifier) @font-lock-function-call-face)
     (package_apply_statement
      name: (package_statement_identifier) @font-lock-function-call-face)
     (binary_expression
      _ "|>" (qualified_identifier
               [(lowercase_identifier) (dot_lowercase_identifier)] @font-lock-function-call-face))
     (binary_expression
      (qualified_identifier
       [(lowercase_identifier) (dot_lowercase_identifier)] @font-lock-function-call-face) "<|" _)))
  "Tree-sitter font-lock rules for MoonBit.")

(defun moonbit--syntax-propertize (beg end)
  "Mark literal and interpolation syntax between BEG and END."
  (let ((root (treesit-buffer-root-node 'moonbit))
        (fence (string-to-syntax "|"))
        (punctuation (string-to-syntax ".")))
    (dolist (capture
             (treesit-query-capture
              root '([(char_literal) (byte_literal) (string_interpolation)
                      (multiline_string_fragment) (multiline_interpolation_fragment)
                      (multiline_string_content) (multiline_interpolation_content)
                      (interpolator)] @literal)
              beg end))
      (let* ((node (cdr capture))
             (type (treesit-node-type node))
             (start (treesit-node-start node))
             (finish (treesit-node-end node)))
        (pcase type
          ((or "char_literal" "byte_literal")
           (let ((open (+ start (if (equal type "byte_literal") 1 0))))
             (when (eq (char-after open) ?')
               (put-text-property open (1+ open) 'syntax-table (string-to-syntax "\"")))
             (when (eq (char-before finish) ?')
               (put-text-property (1- finish) finish 'syntax-table (string-to-syntax "\"")))))
          ("string_interpolation"
           (put-text-property start (1+ start) 'syntax-table fence)
           (when (eq (char-before finish) ?\")
             (put-text-property (1- finish) finish 'syntax-table fence)))
          ((or "multiline_string_fragment" "multiline_interpolation_fragment")
           (put-text-property start (1+ start) 'syntax-table fence)
           ;; The parser can leave trailing whitespace outside the fragment.
           (let ((close (save-excursion (goto-char finish) (line-end-position))))
             (when (eq (char-after close) ?\n)
               (put-text-property close (1+ close) 'syntax-table fence))
             (put-text-property start (min (point-max) (1+ close)) 'syntax-multiline t)))
          ((or "multiline_string_content" "multiline_interpolation_content")
           ;; Raw text does not let a backslash escape its closing fence.
           (unless (treesit-node-child node 0 t)
             (save-excursion
               (goto-char start)
               (while (search-forward "\\" finish t)
                 (put-text-property (1- (point)) (point) 'syntax-table punctuation)))))
          ("interpolator"
           ;; The braces close and reopen the surrounding generic string.
           (put-text-property start (1+ start) 'syntax-table punctuation)
           (put-text-property (1+ start) (+ start 2) 'syntax-table fence)
           (when (eq (char-before finish) ?})
             (put-text-property (1- finish) finish 'syntax-table fence))))
        (put-text-property start finish 'syntax-multiline t)))))

(defun moonbit--after-attributes-p (node _parent _bol)
  "Return non-nil when NODE follows declaration attributes."
  (equal (treesit-node-type (treesit-node-prev-sibling node)) "attributes"))

(defun moonbit--unfinished-indent-anchor (_node _parent bol)
  "Return a local indentation anchor for an unfinished line at BOL."
  (save-excursion
    (goto-char bol)
    (let ((open (nth 1 (syntax-ppss))))
      (forward-line -1)
      (end-of-line)
      (skip-chars-backward " \t")
      (cond
       ((looking-back "=>" (line-beginning-position))
        (back-to-indentation) (point))
       (open (goto-char open) (back-to-indentation) (point))))))

(defun moonbit--unfinished-line-p (node parent bol)
  "Return non-nil if a partial tree at BOL needs a local indent anchor."
  (and (or (null node) (equal (treesit-node-type parent) "ERROR"))
       (moonbit--unfinished-indent-anchor node parent bol)))

(defun moonbit--string-line-p (_node _parent bol)
  "Return non-nil if the whitespace on BOL's line is string data."
  (let* ((line-start (save-excursion (goto-char bol) (line-beginning-position)))
         (node (treesit-node-at line-start 'moonbit)))
    (catch 'result
      (while node
        (let ((type (treesit-node-type node)))
          ;; Whitespace inside a multiline interpolation expression is code.
          (when (and (equal type "interpolator")
                     (< (treesit-node-start node) line-start))
            (throw 'result nil))
          (when (member type '("string_literal" "string_interpolation"
                               "bytes_literal" "regex_literal"))
            (throw 'result (< (treesit-node-start node) line-start))))
        (setq node (treesit-node-parent node))))))

(defvar moonbit--treesit-indent-rules
  `((moonbit
     ;; Do not change the contents of strings or block comments.
     (moonbit--string-line-p no-indent 0)
     ((parent-is ,(rx bos (or "string_fragment" "unescaped_string_fragment"
                             "multiline_string_content" "multiline_interpolation_content"
                             "block_comment") eos)) no-indent 0)
     ((node-is "\\`[]})]\\'") parent-bol 0)
     (moonbit--unfinished-line-p moonbit--unfinished-indent-anchor moonbit-indent-offset)
     ((parent-is "\\`structure\\'") column-0 0)
     (moonbit--after-attributes-p parent-bol 0)
     ((parent-is "\\`multiline_string_literal\\'") parent 0)
     ;; The first multiline fragment is a continuation of its let/assignment.
     ((node-is "\\`multiline_string_literal\\'") parent-bol moonbit-indent-offset)
     ((parent-is ,(rx bos (or "block_expression" "nonempty_block_expression"
                             "struct_definition" "enum_definition" "extenum_definition"
                             "extenum_extension" "error_type_definition" "trait_definition"
                             "match_expression" "lexmatch_expression" "lexscan_expression"
                             "arguments" "parameters" "array_expression" "tuple_expression"
                             "parenthesized_expression" "map_expression" "struct_expression"
                             "import_declaration" "package_apply_statement"
                             "package_array_expression" "package_map_expression"
                             "attribute_properties" "type_parameters"
                             "trait_method_extension") eos))
      parent-bol moonbit-indent-offset)
     ((parent-is ,(rx (or "_definition" "_expression" "_clause") eos))
      parent-bol moonbit-indent-offset)
     (catch-all parent-bol 0)))
  "Tree-sitter indentation rules for MoonBit.")

(defun moonbit--child-of-type (node types)
  "Return the first named child of NODE whose type is in TYPES."
  (cl-find-if (lambda (child) (member (treesit-node-type child) types))
              (treesit-node-children node t)))

(defun moonbit--treesit-defun-name (node)
  "Return a stable name for the definition NODE."
  (let* ((type (treesit-node-type node))
         (name (moonbit--child-of-type
                node '("function_identifier" "identifier" "lowercase_identifier"
                       "uppercase_identifier" "string_literal" "type_alias_targets"
                       "trait_alias_targets" "function_alias_targets"))))
    (cond
     ((equal type "test_definition")
      (if name (treesit-node-text name t) "test"))
     ((equal type "extenum_extension")
      (let ((package (moonbit--child-of-type node '("package_identifier")))
            (target (moonbit--child-of-type node '("dot_uppercase_identifier"))))
        (if package
            (concat (treesit-node-text package t) (treesit-node-text target t))
          (treesit-node-text name t))))
     ((member type '("impl_definition" "impl_declaration"))
      (let* ((trait (moonbit--child-of-type node '("type_name")))
             (target (and trait (treesit-node-next-sibling trait t))))
        (concat (treesit-node-text trait t)
                (when (and target
                           (not (member (treesit-node-type target)
                                        '("function_identifier" "parameters"))))
                  (concat " for " (treesit-node-text target t)))
                (when name (concat "::" (treesit-node-text name t))))))
     (name (treesit-node-text name t)))))

(defun moonbit-mode--ts-setup ()
  "Set up tree-sitter for MoonBit."
  (treesit-parser-create 'moonbit)
  (setq-local syntax-propertize-function #'moonbit--syntax-propertize)
  (add-hook 'syntax-propertize-extend-region-functions
            #'syntax-propertize-multiline nil t)
  (setq-local treesit-font-lock-feature-list
              '((comment definition) (keyword string literal)
                (attribute identifier function operator bracket delimiter)))
  (setq-local treesit-font-lock-settings
              (apply #'treesit-font-lock-rules moonbit--font-lock-rules))
  (setq-local treesit-simple-indent-rules moonbit--treesit-indent-rules)
  (setq-local treesit-defun-type-regexp
              (rx bos (or "function_definition" "named_lambda_expression"
                          "test_definition" "value_definition" "const_definition"
                          "struct_definition" "tuple_struct_definition" "enum_definition"
                          "extenum_definition" "extenum_extension" "type_definition"
                          "error_type_definition" "trait_definition" "impl_definition"
                          "impl_declaration" "type_alias_definition"
                          "trait_alias_definition" "function_alias_definition") eos))
  (setq-local treesit-defun-name-function #'moonbit--treesit-defun-name)
  (setq-local treesit-simple-imenu-settings
              '(("Function" "\\`function_definition\\'" nil nil)
                ("Value" "\\`\\(?:value\\|const\\)_definition\\'" nil nil)
                ("Struct" "\\`\\(?:struct\\|tuple_struct\\)_definition\\'" nil nil)
                ("Enum" "\\`\\(?:enum_definition\\|extenum_definition\\|extenum_extension\\)\\'" nil nil)
                ("Type" "\\`\\(?:type\\|error_type\\)_definition\\'" nil nil)
                ("Trait" "\\`trait_definition\\'" nil nil)
                ("Impl" "\\`impl_\\(?:definition\\|declaration\\)\\'" nil nil)
                ("Alias" "\\`\\(?:type\\|trait\\|function\\)_alias_definition\\'" nil nil)
                ("Test" "\\`test_definition\\'" nil nil)))
  (treesit-major-mode-setup))

;;;###autoload
(define-derived-mode moonbit-mode prog-mode "MoonBit"
  "Major mode for editing MoonBit source, interfaces and configuration."
  :syntax-table moonbit-mode-syntax-table
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "//+\\s-*")
  (setq-local indent-tabs-mode nil)
  (setq-local compile-command moonbit-compile-command)
  (when (treesit-ready-p 'moonbit)
    (moonbit-mode--ts-setup)))

(defvar eglot-server-programs)

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(moonbit-mode . ("moon" "lsp"))))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.mbti?\\'" . moonbit-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\(?:\\`\\|/\\)moon\\.\\(?:mod\\|pkg\\|work\\)\\'" . moonbit-mode))

(provide 'moonbit-mode)

;;; moonbit-mode.el ends here
