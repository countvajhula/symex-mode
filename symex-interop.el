;;; symex-interop.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Interoperability with editing workflows, specifically towards supporting
;; either evil-based or vanilla Emacs editing in conjunction with
;; symex mode.

;;; Code:

(require 'symex-custom
         'symex-primitives)

;; to avoid byte compile warnings.  eventually sort out the dependency
;; order so this is unnecessary
(defvar chimera-symex-mode)
(defvar rigpa-mode)

;; misc bindings defined elsewhere
(declare-function rigpa-enter-higher-level "ext:ignore")
(declare-function rigpa-enter-lower-level "ext:ignore")
(declare-function rigpa-enter-lowest-level "ext:ignore")
(declare-function chimera-hydra-portend-exit "ext:ignore")
(declare-function chimera-hydra-signal-exit "ext:ignore")
(declare-function chimera-handle-hydra-exit "ext:ignore")

(defvar-local symex--original-scroll-margin nil)
(defvar-local symex--original-max-scroll-margin nil)

(defun symex--adjust-point-on-entry ()
  "Adjust point context from the Emacs to the Vim interpretation.

If entering symex mode from Insert or Emacs mode, then translate point
so it indicates the appropriate symex in Symex mode.  This is necessary
because in Emacs, the symex preceding point is indicated.  In Vim, the
symex \"under\" point is indicated.  We want to make sure to select the
right symex when we enter Symex mode."
  (interactive)
  (when (or (not (symex--evil-installed-p))
            (symex--evil-disabled-p)
            (member evil-state '(insert emacs)))
    (symex--adjust-point)))

(defun symex--rigpa-installed-p ()
  "Check if rigpa is installed."
  (boundp 'rigpa-mode))

(defun symex--rigpa-enabled-p ()
  "Check if rigpa is enabled."
  (and (symex--rigpa-installed-p) rigpa-mode))

(defun symex--evil-installed-p ()
  "Check if evil is installed."
  (boundp 'evil-mode))

(defun symex--evil-enabled-p ()
  "Check if evil is enabled."
  (and (symex--evil-installed-p) evil-mode))

(defun symex--evil-disabled-p ()
  "Check if evil is disabled."
  (and (symex--evil-installed-p) (not evil-mode)))

(defun symex-escape-higher ()
  "Exit symex mode via an \"escape\"."
  (interactive)
  (cond ((symex--rigpa-enabled-p)
         (rigpa-enter-higher-level))
        ((symex--evil-enabled-p)
         (evil-normal-state))
        (t (evil-emacs-state))))

(defun symex-enter-lower ()
  "Exit symex mode via an \"enter\"."
  (interactive)
  (cond ((symex--rigpa-enabled-p)
         (rigpa-enter-lower-level))
        ((symex--evil-enabled-p)
         (evil-insert-state))
        (t (evil-emacs-state))))

(defun symex-enter-lowest ()
  "Enter the lowest (manual) editing level."
  (interactive)
  (cond ((symex--rigpa-enabled-p)
         (rigpa-enter-lowest-level)
         ;; TODO: generalize so that commands specifically entering
         ;; another level (esp the lowest) clear any recall flags;
         ;; on the other hand, it may be desirable to retain it but
         ;; override it temporarily, so that exiting the lowest level
         ;; via normal exits (e.g. Esc) returns to the prior state
         (chimera-hydra-portend-exit chimera-symex-mode))
        ((symex--evil-enabled-p)
         (evil-insert-state))
        (t (evil-emacs-state))))

(defun symex--set-scroll-margin ()
  "Set a convenient scroll margin for symex mode, after storing the original value."
  (unless symex--original-scroll-margin
    ;; only set these the first time symex mode is entered in the buffer
    ;; do they need to be buffer-local, though?
    (setq-local symex--original-scroll-margin scroll-margin)
    (setq-local symex--original-max-scroll-margin maximum-scroll-margin))
  (setq-local scroll-margin 9999)
  (setq-local maximum-scroll-margin 0.368))

(defun symex--restore-scroll-margin ()
  "Restore original `scroll-margin` (e.g. upon symex exit)."
  (setq-local scroll-margin symex--original-scroll-margin)
  (setq-local maximum-scroll-margin symex--original-max-scroll-margin))

(defun symex--signal-exit ()
  "Witness symex exit and take appropriate action."
  (when (symex--rigpa-enabled-p)
    (chimera-hydra-signal-exit chimera-symex-mode
                               #'chimera-handle-hydra-exit)))

;; TODO: these are only here because there's no good "pass through" option
;; to use whatever scrolling (or other) command is mapped to e.g. C-e and C-y
;; outside of the hydra
(defun symex--scroll-down ()
  "Scroll view down."
  (interactive)
  (evil-scroll-line-down 3))

(defun symex--scroll-up ()
  "Scroll view up."
  (interactive)
  (evil-scroll-line-up 3))


(provide 'symex-interop)
;;; symex-interop.el ends here
