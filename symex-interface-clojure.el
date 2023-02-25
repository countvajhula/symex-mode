;;; symex-interface-clojure.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Interface for the Clojure language

;;; Code:

(require 'cider nil 'noerror)
(require 'symex-interop)
(require 'symex-interface)

(declare-function cider-eval-last-sexp "ext:cider")
(declare-function cider-eval-defun-at-point "ext:cider")
(declare-function cider-pprint-eval-last-sexp "ext:cider")
(declare-function cider-eval-print-last-sexp "ext:cider")
(declare-function cider-doc "ext:cider")
(declare-function cider-switch-to-repl-buffer "ext:cider")
(declare-function cider-eval-buffer "ext:cider")

(defun symex-eval-definition-clojure ()
  "Eval entire containing definition."
  (cider-eval-defun-at-point nil))

(defun symex-describe-symbol-clojure ()
  "Describe symbol at point."
  (cider-doc nil))

(defun symex-repl-clojure ()
  "Go to REPL."
  ;; this already goes to the active repl prompt
  ;; so there's no need to move point there
  (cider-switch-to-repl-buffer)
  (symex-enter-lowest))

(defun symex-switch-to-scratch-buffer-clojure ()
  "Switch to scratch buffer."
  (let ((buffer-name "*scratch - Clojure*"))
    (switch-to-buffer (or (get-buffer buffer-name)
                          (symex--new-scratch-buffer buffer-name)))))

(defvar symex-clojure-modes (list 'clojure-mode
                                  'clojurescript-mode
                                  'clojurec-mode))

(defun symex-interface-register-clojure ()
  "Register the Clojure runtime interface."
  (symex-interface-extend
   symex-clojure-modes
   (list
    :eval #'cider-eval-last-sexp
    :eval-definition #'symex-eval-definition-clojure
    :eval-pretty #'cider-pprint-eval-last-sexp
    :eval-print #'cider-eval-print-last-sexp
    :describe-symbol #'symex-describe-symbol-clojure
    :repl #'symex-repl-clojure
    :run #'cider-eval-buffer
    :switch-to-scratch-buffer #'symex-switch-to-scratch-buffer-clojure)))

(provide 'symex-interface-clojure)
;;; symex-interface-clojure.el ends here
