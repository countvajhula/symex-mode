;;; symex-interface-arc.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Interface for the Arc language

;;; Code:

(require 'arc nil 'noerror)
(require 'symex-interop)
(require 'symex-interface)

(declare-function arc-send-last-sexp "ext:arc")
(declare-function arc-send-definition "ext:arc")
(declare-function arc--repl-last-sexp-start "ext:arc")
(declare-function arc--send-to-repl "ext:arc")
(declare-function arc-repl "ext:arc")

(defun symex-eval-thunk-arc ()
  "Evaluate symex as a \"thunk,\" i.e. as a function taking no arguments."
  (let ((thunk-code (string-join
                     `("("
                       ,(buffer-substring (arc--repl-last-sexp-start)
                                          (point))
                       ")"))))
    (arc--send-to-repl thunk-code)))

(defun symex-repl-arc ()
  "Go to REPL."
  (arc-repl)
  (goto-char (point-max))
  (symex-enter-lowest))

(defun symex-switch-to-scratch-buffer-arc ()
  "Switch to scratch buffer."
  (let ((buffer-name "*scratch - Arc*"))
    (switch-to-buffer (or (get-buffer buffer-name)
                          (symex--new-scratch-buffer buffer-name)))))

(defvar symex-arc-modes (list 'arc-mode))

(defun symex-interface-register-arc ()
  "Register the Arc runtime interface."
  (symex-interface-extend
   symex-arc-modes
   (list
    :eval #'arc-send-last-sexp
    :eval-definition #'arc-send-definition
    :eval-pretty #'arc-send-last-sexp
    :eval-thunk #'symex-eval-thunk-arc
    :repl #'symex-repl-arc
    :switch-to-scratch-buffer #'symex-switch-to-scratch-buffer-arc)))


(provide 'symex-interface-arc)
;;; symex-interface-arc.el ends here
