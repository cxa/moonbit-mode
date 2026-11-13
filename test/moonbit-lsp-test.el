;;; moonbit-lsp-test.el --- Live native LSP regression -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'warnings)
(require 'moonbit-mode)
(require 'eglot)
(require 'flymake)
(require 'xref)

(when-let* ((directory (getenv "MOONBIT_TEST_GRAMMAR_DIR")))
  (add-to-list 'treesit-extra-load-path directory))

(defun moonbit-lsp-test--wait (predicate)
  "Wait up to 15 seconds for PREDICATE, processing server output."
  (let ((deadline (+ (float-time) 15)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.1))
    (should (funcall predicate))))

(defun moonbit-lsp-test--errors ()
  "Return Eglot error diagnostics in the current buffer."
  (cl-remove-if-not
   (lambda (diagnostic) (eq (flymake-diagnostic-type diagnostic) 'eglot-error))
   (flymake-diagnostics)))

(defun moonbit-lsp-test--replace-buffer (text)
  "Replace current buffer with TEXT and send it to the server."
  (erase-buffer)
  (insert text)
  (eglot--signal-textDocument/didChange)
  (flymake-start))

(ert-deftest moonbit-lsp-test-native-eglot ()
  "Exercise the registered native server through actual Eglot services."
  (should (executable-find "moon"))
  (should (executable-find "moon-lsp"))
  (let* ((root (file-name-as-directory (file-truename (make-temp-file "moonbit-lsp-test-" t))))
         (default-directory root)
         (eglot-sync-connect t)
         (eglot-connect-timeout 20)
         (eglot-autoreconnect nil)
         (warning-suppress-log-types '((treesit)))
         (warning-suppress-types '((treesit)))
         (valid-source "pub fn compute() -> Int32 {\n  add_one(41)\n}\n")
         server notifications
         (notification-hook
          (lambda (incoming-server method &rest params)
            (when (and (eq incoming-server server)
                       (memq method '(textDocument/publishDiagnostics :textDocument/publishDiagnostics))
                       (equal (plist-get params :uri)
                              (eglot-path-to-uri (expand-file-name "src/main.mbt" root))))
              (push params notifications)))))
    (unwind-protect
        (progn
          (advice-add 'eglot-handle-notification :before notification-hook)
          (dolist (file `(("moon.mod" . "name = \"test/moonbit_mode_lsp\"\nversion = \"0.1.0\"\n")
                          ("src/moon.pkg" . "")
                          ("src/lib.mbt" . "pub fn add_one(value : Int32) -> Int32 {\n  value + 1\n}\n")
                          ("src/main.mbt" . ,valid-source)))
            (make-directory (file-name-directory (expand-file-name (car file) root)) t)
            (with-temp-file (expand-file-name (car file) root) (insert (cdr file))))
          (with-temp-buffer
            (should (zerop (call-process "moon" nil (current-buffer) nil "check"))))
          (with-current-buffer (find-file-noselect (expand-file-name "src/main.mbt" root))
            (should (eq major-mode 'moonbit-mode))
            ;; Use the mode's registration and normal Eglot project/contact lookup.
            (should (equal (nth 3 (eglot--guess-contact)) '("moon" "lsp")))
            (should (equal (project-root (nth 1 (eglot--guess-contact))) root))
            (should (equal default-directory (expand-file-name "src/" root)))
            (setq server (apply #'eglot (eglot--guess-contact)))
            (should (eglot-managed-p))
            (should (jsonrpc-running-p server))
            (should (memq #'eglot-completion-at-point completion-at-point-functions))
            (message "[live LSP] connected using moonbit-mode's moon lsp registration")

            (goto-char (point-min))
            (search-forward "add_one")
            (backward-char 2)
            (let ((hover (eglot--request server :textDocument/hover
                                         (eglot--TextDocumentPositionParams) :timeout 15)))
              (should (string-match-p "add_one(value" (plist-get (plist-get hover :contents) :value))))
            (let* ((definitions (xref-backend-definitions 'eglot (xref-backend-identifier-at-point 'eglot)))
                   (location (xref-item-location (car definitions))))
              (should (equal (file-truename (xref-file-location-file location))
                             (expand-file-name "src/lib.mbt" root)))
              (should (= (xref-file-location-line location) 1)))
            (message "[live LSP] hover and cross-file definition lookup passed")

            (goto-char (point-min))
            (search-forward "add_one")
            (delete-region (- (point) 7) (point))
            (insert "add_")
            (let* ((capf (eglot-completion-at-point))
                   (prefix (buffer-substring-no-properties (nth 0 capf) (nth 1 capf)))
                   (candidates (all-completions prefix (nth 2 capf)
                                               (plist-get (nthcdr 3 capf) :predicate))))
              (should (member "add_one" (mapcar #'substring-no-properties candidates))))
            (message "[live LSP] completion-at-point returned add_one")

            (moonbit-lsp-test--replace-buffer
             "pub fn compute() -> Int32 {\n  add_one(\"bad\")\n}\n")
            (moonbit-lsp-test--wait #'moonbit-lsp-test--errors)
            (should (cl-some (lambda (diagnostic)
                               (string-match-p "String" (flymake-diagnostic-text diagnostic)))
                             (moonbit-lsp-test--errors)))
            (setq notifications nil)
            (moonbit-lsp-test--replace-buffer valid-source)
            (moonbit-lsp-test--wait
             (lambda ()
               (and (cl-some (lambda (params) (zerop (length (plist-get params :diagnostics))))
                             notifications)
                    (null (moonbit-lsp-test--errors)))))
            (message "[live LSP] Flymake received the type error and cleared it after correction")

            (moonbit-lsp-test--replace-buffer "pub fn compute()->Int32{add_one(41)}\n")
            (eglot-format-buffer)
            (should (string-match-p (regexp-quote "pub fn compute() -> Int32 {") (buffer-string)))
            (should (string-match-p (regexp-quote "\n  add_one(41)\n}") (buffer-string)))
            (message "[live LSP] eglot-format-buffer applied server edits"))

          (dolist (file-and-key '(("moon.mod" . "name") ("src/moon.pkg" . "import")))
            (with-current-buffer (find-file-noselect (expand-file-name (car file-and-key) root))
              (should (eq major-mode 'moonbit-mode))
              (should (eglot-managed-p))
              (should (eq (eglot-current-server) server))
              (goto-char (point-max))
              (insert "\n")
              (let* ((capf (eglot-completion-at-point))
                     (candidates (all-completions "" (nth 2 capf))))
                (should (member (cdr file-and-key) (mapcar #'substring-no-properties candidates))))
              (message "[live LSP] %s shared the server and returned configuration completions" (car file-and-key)))))
      (advice-remove 'eglot-handle-notification notification-hook)
      (when server
        (when-let* ((directory (getenv "MOONBIT_LSP_TEST_LOG_DIR")))
          (make-directory directory t)
          (with-current-buffer (jsonrpc-events-buffer server)
            (let ((coding-system-for-write 'no-conversion))
              (write-region (point-min) (point-max)
                            (expand-file-name "eglot-events.log" directory) nil 'silent))))
        (ignore-errors (eglot-shutdown server)))
      (dolist (buffer (buffer-list))
        (when (and (buffer-file-name buffer)
                   (file-in-directory-p (buffer-file-name buffer) root))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory root t))))

;;; moonbit-lsp-test.el ends here
