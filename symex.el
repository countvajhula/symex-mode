;;; symex.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

;; Author: Siddhartha Kasivajhula <sid@countvajhula.com>
;; URL: https://github.com/countvajhula/symex.el
;; Version: 1.0
;; Package-Requires: ((emacs "25.1") (lispy "0.26.0") (paredit "24") (evil-cleverparens "20170718.413") (evil "1.2.14") (evil-surround "1.0.4") (hydra "0.15.0") (seq "2.22") (undo-tree "0.7.5"))
;; Keywords: lisp, convenience, languages

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

;; Symex mode (pronounced sym-ex, as in symbolic expression) is a vim-
;; inspired way of editing Lisp code as trees.  Entering symex mode
;; allows you to reason about your code in terms of its structure,
;; similar to other tools like paredit and lispy.  But while in those
;; packages the tree representation is implicit, symex mode models
;; the tree structure explicitly so that tree navigations and operations
;; can be described using an expressive DSL, and invoked in a vim-
;; style modal interface implemented with a Hydra.
;;
;; At the moment, symex mode uses paredit, lispy, and evil-cleverparens
;; to provide much of its low level functionality.
;; In the future, this layer of primitives may be replaced with a layer
;; that explicitly uses the abstract syntax tree, for greater precision.

;;; Code:

(require 'lispy)

(require 'symex-hydra)
(require 'symex-evil)
(require 'symex-interop)
(require 'symex-misc)
(require 'symex-custom)

;;;###autoload
(define-minor-mode symex-mode
  "An evil way to edit Lisp symbolic expressions as trees."
  :lighter " symex"
  :keymap (let ((symex-map (make-sparse-keymap)))
            (define-key
              symex-map
              (kbd "(")
              #'paredit-open-round)

            (define-key
              symex-map
              (kbd ")")
              #'paredit-close-round)

            (define-key
              symex-map
              (kbd "[")
              #'paredit-open-square)

            (define-key
              symex-map
              (kbd "]")
              #'paredit-close-square)

            (define-key
              symex-map
              (kbd "<backspace>")
              #'paredit-backward-delete)

            (define-key
              symex-map
              (kbd "<DEL>")
              #'paredit-backward-delete)

            (define-key
              symex-map
              (kbd "\"")
              #'paredit-doublequote)

            symex-map))

(defun symex--ensure-minor-mode ()
  "Enable symex minor mode if it isn't already enabled."
  (unless symex-mode
    (symex-mode)))

(defun symex--enter-mode ()
  "Load the modal interface."
  (cond ((eq symex-modal-backend 'hydra) (hydra-symex/body))
        ((eq symex-modal-backend 'evil)
         (unless (symex--rigpa-enabled-p)
           ;; the minor mode needs to be enabled prior to entering the
           ;; evil state or the keybindings won't take effect. So we
           ;; can't do it in the state entry hook, which would
           ;; otherwise be preferable
           (symex-enable-editing-minor-mode))
         (evil-symex-state))))

(defun symex-enter-mode ()
  "Take necessary action upon symex mode entry."
  (symex--ensure-minor-mode)
  (symex--adjust-point-on-entry)
  (when symex-remember-branch-positions-p
    (symex--clear-branch-memory))
  (symex-select-nearest)
  (when symex-refocus-p
    ;; smooth scrolling currently not supported
    ;; may add it back in the future
    (symex--set-scroll-margin))
  (symex--enter-mode))

;;; Major modes in which symex should be active.
(defvar symex-elisp-modes (list 'lisp-interaction-mode
                                'emacs-lisp-mode
                                'inferior-emacs-lisp-mode))

(defvar symex-racket-modes (list 'racket-mode
                                 'racket-repl-mode))

(defvar symex-clojure-modes (list 'clojure-mode
                                  'clojurescript-mode
                                  'clojurec-mode))

(defvar symex-lisp-modes (append symex-elisp-modes
                                 symex-racket-modes
                                 symex-clojure-modes
                                 (list 'scheme-mode
                                       'arc-mode
                                       'lisp-mode)))

;;;###autoload
(defun symex-initialize ()
  "Initialize symex mode.

This registers symex mode for use in all recognized Lisp modes, and also
advises functions to enable or disable features based on user configuration."
  ;; enable the symex minor mode in all recognized lisp modes
  (dolist (mode-name symex-lisp-modes)
    (let ((mode-hook (intern (concat (symbol-name mode-name)
                                     "-hook"))))
      (add-hook mode-hook 'symex-mode)))
  ;; advise functions to enable or disable configured features
  (when symex-remember-branch-positions-p
    (advice-add #'symex-go-in :around #'symex--remember-branch-position)
    (advice-add #'symex-go-out :around #'symex--return-to-branch-position)
    (advice-add #'symex-go-backward :around #'symex--forget-branch-positions)
    (advice-add #'symex-go-forward :around #'symex--forget-branch-positions))
  (symex--add-selection-advice)
  ;; initialize modal interface frontend
  (cond ((eq symex-modal-backend 'hydra)
         (symex-hydra-initialize))
        ((eq symex-modal-backend 'evil)
         (symex-evil-initialize))))

(defun symex-disable ()
  "Disable symex.

This unregisters the symex minor mode from all lisp-related hooks, and
removes any advice corresponding to configured features.

If you are changing symex customizations to enable or disable certain
features, you may need to call this function after making such changes
and prior to calling `symex-initialize` again, in order for the former
configuration to be disabled and the new one adopted."
  (dolist (mode-name symex-lisp-modes)
    (let ((mode-hook (intern (concat (symbol-name mode-name)
                                     "-hook"))))
      (remove-hook mode-hook 'symex-mode)))
  ;; remove all advice
  (advice-remove #'symex-go-in #'symex--remember-branch-position)
  (advice-remove #'symex-go-out #'symex--return-to-branch-position)
  (advice-remove #'symex-go-backward #'symex--forget-branch-positions)
  (advice-remove #'symex-go-forward #'symex--forget-branch-positions)
  (symex--remove-selection-advice))

;;;###autoload
(defun symex-mode-interface ()
  "The main entry point for editing symbolic expressions using symex mode.

Enter the symex evil state and show a hydra menu for accessing various
features."
  (interactive)
  (symex-enter-mode))


(provide 'symex)
;;; symex.el ends here
