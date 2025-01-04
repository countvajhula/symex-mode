;;; symex-interface-racket.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

;; URL: https://github.com/drym-org/symex.el

;; This program is "part of the world," in the sense described at
;; https://drym.org.  From your perspective, this is no different than
;; MIT or BSD or other such "liberal" licenses that you may be
;; familiar with, that is to say, you are free to do whatever you like
;; with this program.  It is much more than BSD or MIT, however, in
;; that it isn't a license at all but an idea about the world and how
;; economic systems could be set up so that everyone wins.  Learn more
;; at drym.org.
;;
;; This work transcends traditional legal and economic systems, but
;; for the purposes of any such systems within which you may need to
;; operate:
;;
;; This is free and unencumbered software released into the public domain.
;; The authors relinquish any copyright claims on this work.
;;

;;; Commentary:

;; Interface for the Racket language

;;; Code:

(require 'racket-mode nil 'noerror)
(require 'subr-x)
(require 'symex-interop)
(require 'symex-primitives)
(require 'symex-interface)

;; from racket-mode - avoid byte-compile warnings
(defvar racket-repl-buffer-name)
(defvar racket-xp-mode)

(declare-function racket-repl "ext:racket-mode")
(declare-function racket--repl-forget-errors "ext:racket-mode")
(declare-function with-racket-repl-buffer "ext:racket-mode")
(declare-function racket-send-last-sexp "ext:racket-mode")
(declare-function racket-send-definition "ext:racket-mode")
(declare-function racket-xp-describe "ext:racket-mode")
(declare-function racket-repl-describe "ext:racket-mode")
(declare-function racket-run "ext:racket-mode")

(defun symex--racket-send-to-repl (code)
   "Send CODE to the current buffer's REPL for evaluation.

Based on `racket--send-region-to-repl' from `racket-mode'."
  (unless (racket--repl-session-id)
    (user-error "No REPL session available; run the file first"))
  ;; Capture source buffer in case something changes; see e.g. #407.
  (let ((source-buffer (current-buffer)))
    (racket--repl-forget-errors)
    (with-racket-repl-buffer
      (save-excursion
        (racket--repl-delete-prompt-mark nil)
        (goto-char (point-max))
        (insert ?\n)
        (when t
          (insert code)
          (insert (propertize "\n=>\n"
                              'font-lock-face 'racket-repl-message)))
        (add-text-properties racket--repl-output-mark (point)
                             (list 'field 'send
                                   'read-only t))
        (set-marker racket--repl-output-mark (point))))
    (racket--cmd/async (racket--repl-session-id)
                       `(repl-submit ,code))
    (display-buffer racket-repl-buffer-name)))

(defun symex-eval-racket ()
  "Eval last sexp.

Accounts for different point location in evil vs Emacs mode."
  (save-excursion
    (when (equal evil-state 'normal)
      (forward-char))
    (racket-send-last-sexp)))

(defun symex-eval-pretty-racket ()
  "Evaluate symex and render the result in a useful string form."
  (let ((pretty-code (string-join
                      `("(let ([result "
                        ,(buffer-substring (symex--get-starting-point)
                                           (point))
                        "])"
                        " (cond [(stream? result) (stream->list result)]
                                  [(sequence? result) (sequence->list result)]
                                  [else result]))"))))
    (symex--racket-send-to-repl pretty-code)))

(defun symex-eval-thunk-racket ()
  "Evaluate symex as a \"thunk,\" i.e. as a function taking no arguments."
  (let ((thunk-code (string-join
                     `("("
                       ,(buffer-substring (symex--get-starting-point)
                                          (point))
                       ")"))))
    (symex--racket-send-to-repl thunk-code)))

(defun symex-describe-symbol-racket ()
  "Describe symbol at point."
  (let ((original-window (selected-window)))
    (cond (racket-xp-mode (racket-xp-describe))
          ((eq major-mode 'racket-repl-mode) (racket-repl-describe))
          (t (error "Enable racket-xp-mode or start the REPL!")))
    (select-window original-window)))

(defun symex-repl-racket ()
  "Go to REPL."
  (let ((original-window (selected-window)))
    (racket-edit-switch-to-repl)
    (unless (eq original-window (selected-window))
      ;; if the REPL window is currently being created
      ;; then don't attempt to go to the bottom
      (goto-char (point-max))
      (symex-enter-lowest))))

(defun symex-switch-to-scratch-buffer-racket ()
  "Switch to scratch buffer."
  (let ((buffer-name "*scratch - Racket*"))
    (switch-to-buffer (or (get-buffer buffer-name)
                          (symex--new-scratch-buffer buffer-name)))))

(defvar symex-racket-modes (list 'racket-mode
                                 'racket-repl-mode))

(defun symex-interface-register-racket ()
  "Register the Racket runtime interface."
  (symex-interface-extend
   symex-racket-modes
   (list
    :eval #'symex-eval-racket
    :eval-definition #'racket-send-definition
    :eval-pretty #'symex-eval-pretty-racket
    :eval-thunk #'symex-eval-thunk-racket
    :describe-symbol #'symex-describe-symbol-racket
    :repl #'symex-repl-racket
    :run #'racket-run
    :switch-to-scratch-buffer #'symex-switch-to-scratch-buffer-racket)))

(provide 'symex-interface-racket)
;;; symex-interface-racket.el ends here
