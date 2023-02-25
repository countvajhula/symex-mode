;;; symex-interface-scheme.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Interface for the Scheme language

;;; Code:

(require 'geiser-mode nil 'noerror)
(require 'symex-interop)
(require 'symex-interface)

(declare-function geiser-eval-last-sexp "ext:geiser-mode")
(declare-function geiser-eval-definition "ext:geiser-mode")
(declare-function geiser-doc-symbol-at-point "ext:geiser-mode")
(declare-function geiser-mode-switch-to-repl "ext:geiser-mode")
(declare-function geiser-eval-buffer "ext:geiser-mode")

(defun symex-eval-scheme ()
  "Eval Scheme symex."
  (geiser-eval-last-sexp nil))

(defun symex-eval-definition-scheme ()
  "Eval entire containing definition."
  (geiser-eval-definition nil))

(defun symex-repl-scheme ()
  "Go to REPL."
  (geiser-mode-switch-to-repl nil)
  (goto-char (point-max))
  (symex-enter-lowest))

(defun symex-run-scheme ()
  "Evaluate buffer."
  (geiser-eval-buffer nil))

(defun symex-switch-to-scratch-buffer-scheme ()
  "Switch to scratch buffer."
  (let ((buffer-name "*scratch - Scheme*"))
    (switch-to-buffer (or (get-buffer buffer-name)
                          (symex--new-scratch-buffer buffer-name)))))

(defvar symex-scheme-modes (list 'scheme-mode))

(defun symex-interface-register-scheme ()
  "Register the Scheme runtime interface."
  (symex-interface-extend
   symex-scheme-modes
   (list
    :eval #'symex-eval-scheme
    :eval-definition #'symex-eval-definition-scheme
    :eval-pretty #'symex-eval-scheme
    :describe-symbol #'geiser-doc-symbol-at-point
    :repl #'symex-repl-scheme
    :run #'symex-run-scheme
    :switch-to-scratch-buffer #'symex-switch-to-scratch-buffer-scheme)))

(provide 'symex-interface-scheme)
;;; symex-interface-scheme.el ends here
