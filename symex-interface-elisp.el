;;; symex-interface-elisp.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Interface for the Elisp language

;;; Code:

(require 'evil nil :no-error)
(require 'symex-interop)

(defun symex-eval-elisp ()
  "Eval Elisp symex."
  (interactive)
  (eval-last-sexp nil))

(defun symex-eval-definition-elisp ()
  "Eval entire containing definition."
  (eval-defun nil))

(defun symex-eval-pretty-elisp ()
  "Evaluate symex and render the result in a useful string form."
  (interactive)
  (symex-eval-elisp))

(defun symex-eval-thunk-elisp ()
  "Evaluate symex as a 'thunk,' i.e. as a function taking no arguments."
  (interactive)
  ;; can use (eval (car (read-from-string thunk-code)))
  (message "eval as thunk currently not supported for ELisp"))

(defun symex-eval-print-elisp ()
  "Eval symex and print result in buffer."
  (interactive)
  (eval-print-last-sexp))

(defun symex-describe-symbol-elisp ()
  "Describe symbol at point."
  (interactive)
  (describe-symbol (symbol-at-point)))

(defun symex-repl-elisp ()
  "Enter elisp REPL, context-aware.

If the REPL is already visible, switch to that window.  Otherwise,
if there is only one window, open REPL in a new window.  Otherwise
open in most recently used other window."
  (interactive)
  (let ((window (get-buffer-window "*ielm*")))
    (cond (window (select-window window))
          ((= 1 (length (window-list)))
           (split-window-right)
           (windmove-right)
           (ielm))
          ((symex--evil-installed-p)
           (evil-window-mru)            ; better LRU
           (ielm))
          (t
           (other-window -1)
           (ielm)))
    (goto-char (point-max))
    (symex-enter-lowest)))

(defun symex-run-elisp ()
  "Evaluate buffer."
  (eval-buffer))


(provide 'symex-interface-elisp)
;;; symex-interface-elisp.el ends here
