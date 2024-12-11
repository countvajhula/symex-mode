;;; symex-lithium.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Lithium modal frontend to symex.

;;; Code:

(require 'lithium)
(require 'cl-lib)

(require 'symex-ui)
(require 'symex-misc)
(require 'symex-transformations)
(require 'symex-interop)
(require 'symex-utils)

(evil-define-state symex
  "Symex state."
  :tag " <λ> "
  :message "-- SYMEX --"
  ;; we currently rely on enabling normal here for support
  ;; for "counts". It would be better to natively support
  ;; counts (i.e. the usual prefix argument), and aim for
  ;; evil to be purely superficial, just for the modeline
  ;; feedback via existing plugins like telephone-line.
  ;; Eventually we could have an analogous modeline extension
  ;; for Lithium, or add Lithium support to existing evil-oriented
  ;; UI extensions
  :enable (normal))

(defun symex-evil-repeat-start-recording-advice (&rest _)
  "Prepare the current command for recording the repetition.

This function is meant to advise `evil-repeat-pre-hook' which
starts recording a repeation during the `pre-command-hook', but
only records a repition when in normal or visual state. This
calls `evil-repeat-start' if the buffer is currently in symex
state."
  (when evil-local-mode
    (let ((repeat-type (evil-repeat-type this-command nil)))
      ;; `evil-repeat-pre-hook' has several paths that it can take and only one
      ;; of them results in `evil-repeat-start' being called. We only need to
      ;; account for the conditions which would have started recording repeat
      ;; information if the buffer were in normal state. That is to say, we only
      ;; start recording if:
      ;;
      ;; 1. The current command has a `:repeat' property that is non-`nil' and
      ;; not set to force abort a repitition
      ;; 2. The current command is not a mouse event
      ;; 3. The buffer is currently in symex state
      (when (and repeat-type
                 (not (evil-repeat-force-abort-p repeat-type))
                 (not (evil-mouse-events-p (this-command-keys)))
                 (evil-symex-state-p))
        (evil-repeat-start)))))

(defun symex-evil-repeat-stop-recording-advice (&rest _)
  "Finish recording of repeat information for the current command.

This function is meant to advise `evil-repeat-post-hook' which
cleans up a recording during the `post-command-hook', but assumes
no recording was started unless the buffer is in normal or visual
state. This calls `evil-repeat-stop' if the buffer is currently
in symex state as well."
  (when (and evil-local-mode evil-recording-repeat)
    (let ((repeat-type (evil-repeat-type this-command t)))
      ;; We only need to call `evil-repeat-stop' if recording would have been
      ;; started by `symex-evil-repeat-start-recording-advice'. If recording was
      ;; started for any other reason, then it will already have been turned off
      ;; by `post-command-hook'. That is to say, we only stop recording if:
      ;;
      ;; 1. The current command has a `:repeat' property that is non-`nil' and
      ;; not set to force abort a repitition
      ;; 2. The current command is not a mouse event
      ;; 3. The buffer is currently in symex state
      (when (and repeat-type
                 (not (evil-repeat-force-abort-p repeat-type))
                 (not (evil-mouse-events-p (this-command-keys)))
                 (evil-symex-state-p))
        (evil-repeat-stop)))))

(defun symex-evil-repeat-preserve-state-advice (orig-fun &rest args)
  "Return to symex state if necessary after calling ORIG-FUN.

This function is meant to advise `evil-repeat' which sets the
buffer to normal state after repeating a command. This first
checks whether the buffer is starting in symex state and, if so,
returns to symex after invoking ORIG-FUN with ARGS."
  (let ((symex-state-p (evil-symex-state-p)))
    (unwind-protect
        (apply orig-fun args)
      (when symex-state-p
        (evil-symex-state)))))

(defun symex--evil-scroll-down ()
  "Scroll down half a page.

This is needed because symex alters scroll margins upon mode entry to
ensure that the symex is always in focus.  For some reason this winds
up causing evil's `evil-scroll-down` to scroll all the way to the
bottom of the buffer.  So we temporarily override the scroll margin in
executing this command to get the expected behavior."
  (interactive)
  (let ((scroll-margin 0))
    (evil-scroll-down nil)))

;; TODO: others that could accept a count argument:
;; simple insert/append
(lithium-define-local-mode symex-editing-mode
  "Symex mode."
  (("h" symex-go-backward)
    ("j" symex-go-down)
    ("k" symex-go-up)
    ("l" symex-go-forward)
    ("gh" backward-char)
    ("gj" symex-next-visual-line)
    ("gk" symex-previous-visual-line)
    ("gl" forward-char)
    ("(" symex-create-round)
    ("[" symex-create-square)
    (")" symex-wrap-round)
    ("]" symex-wrap-square)
    ("C-'" symex-cycle-quote)
    ("C-," symex-cycle-unquote)
    ("`" symex-add-quoting-level)
    ("C-`" symex-remove-quoting-level)
    ("f" symex-traverse-forward)
    ("b" symex-traverse-backward)
    ("C-f" symex-traverse-forward-more)
    ("C-b" symex-traverse-backward-more)
    ("F" symex-traverse-forward-skip)
    ("B" symex-traverse-backward-skip)
    ("{" symex-leap-backward)
    ("}" symex-leap-forward)
    ("M-{" symex-soar-backward)
    ("M-}" symex-soar-forward)
    ("C-k" symex-climb-branch)
    ("C-j" symex-descend-branch)
    ("y" symex-yank)
    ("Y" symex-yank-remaining)
    ("p" symex-paste-after)
    ("P" symex-paste-before)
    ("x" symex-delete)
    ("X" symex-delete-backwards)
    ("D" symex-delete-remaining)
    ("c" symex-change)
    ("C" symex-change-remaining)
    ("C--" symex-clear)
    ("s" symex-replace)
    ("S" symex-change-delimiter)
    ("H" symex-shift-backward)
    ("L" symex-shift-forward)
    ("M-H" symex-shift-backward-most)
    ("M-L" symex-shift-forward-most)
    ("K" paredit-raise-sexp) ; revisit kb
    ("C-S-j" symex-emit-backward)
    ("C-(" symex-capture-backward)
    ("C-S-h" symex-capture-backward)
    ("C-{" symex-emit-backward)
    ("C-S-l" symex-capture-forward)
    ("C-}" symex-emit-forward)
    ("C-S-k" symex-emit-forward)
    ("C-)" symex-capture-forward)
    ("z" symex-swallow)
    ("Z" symex-swallow-tail)
    ("e" symex-evaluate)
    ("E" symex-evaluate-remaining)
    ("C-M-e" symex-evaluate-pretty)
    ("d" symex-evaluate-definition)
    ("M-e" symex-eval-recursive)
    ("T" symex-evaluate-thunk)
    ("t" symex-switch-to-scratch-buffer)
    ("M" symex-switch-to-messages-buffer)
    ("r" symex-repl)
    ("R" symex-run)
    ("|" symex-split)
    ("&" symex-join)
    ("-" symex-splice)
    ("o" symex-open-line-after)
    ("O" symex-open-line-before)
    (">" symex-insert-newline)
    ("<" symex-join-lines-backwards)
    ("C->" symex-append-newline)
    ("C-<" symex-join-lines)
    ("C-S-o" symex-append-newline)
    ("J" symex-join-lines)
    ("M-J" symex-collapse)
    ("M-<" symex-collapse)
    ("M->" symex-unfurl)
    ("C-M-<" symex-collapse-remaining)
    ("C-M->" symex-unfurl-remaining)
    ("0" symex-goto-first)
    ("M-h" symex-goto-first)
    ("$" symex-goto-last)
    ("M-l" symex-goto-last)
    ("M-j" symex-goto-lowest)
    ("M-k" symex-goto-highest)
    ("=" symex-tidy)
    ("<tab>" symex-tidy)
    ("C-=" symex-tidy-remaining)
    ("C-<tab>" symex-tidy-remaining)
    ("M-=" symex-tidy-proper)
    ("M-<tab>" symex-tidy-proper)
    ("A" symex-append-after)
    ("a" symex-insert-at-end)
    ("i" symex-insert-at-beginning)
    ("I" symex-insert-before)
    ("w" symex-wrap)
    ("W" symex-wrap-and-append)
    ("C-d" symex--evil-scroll-down)
    (";" symex-comment)
    ("M-;" symex-comment-remaining)
    ("C-;" symex-eval-print) ; weird pre-offset (in both)
    ("s-;" symex-evaluate)
    ("H-h" symex--toggle-highlight) ; treats visual as distinct mode
    ("C-?" symex-describe)
    ("<return>" symex-enter-lower)
    ("<escape>" symex-escape-higher))
  :lighter " symex"
  :group 'symex)

(defvar symex--evil-repeatable-commands
  '(paredit-raise-sexp
    symex-add-quoting-level
    symex-append-newline
    symex-capture-backward
    symex-capture-forward
    symex-change
    symex-clear
    symex-comment
    symex-comment-remaining
    symex-create-round
    symex-create-square
    symex-cycle-quote
    symex-cycle-unquote
    symex-delete
    symex-delete-backwards
    symex-delete-remaining
    symex-emit-backward
    symex-emit-forward
    symex-insert-newline
    symex-join
    symex-join-lines
    symex-join-lines-backwards
    symex-open-line-after
    symex-open-line-before
    symex-paste-after
    symex-paste-before
    symex-remove-quoting-level
    symex-shift-backward
    symex-shift-backward-most
    symex-shift-forward
    symex-shift-forward-most
    symex-splice
    symex-split
    symex-swallow
    symex-swallow-tail
    symex-tidy
    symex-wrap
    symex-wrap-round
    symex-wrap-square
    symex-append-after
    symex-change-delimiter
    symex-change-remaining
    symex-collapse
    symex-collapse-remaining
    symex-insert-at-beginning
    symex-insert-at-end
    symex-insert-before
    symex-open-line-after
    symex-open-line-before
    symex-tidy-proper
    symex-tidy-remaining
    symex-unfurl
    symex-unfurl-remaining
    symex-wrap-and-append)
  "Commands which should have their `:repeat' property set to t.")

(defun symex-lithium-initialize ()
  "Initialize lithium modal interface."
  (advice-add 'evil-repeat-pre-hook
              :after #'symex-evil-repeat-start-recording-advice)
  (advice-add 'evil-repeat-post-hook
              :after #'symex-evil-repeat-stop-recording-advice)
  (advice-add 'evil-repeat
              :around #'symex-evil-repeat-preserve-state-advice)
  ;; TODO: once all the commands are defined using the macro,
  ;; add this declaration to the macro definition and remove
  ;; the "registration" here.
  (dolist (fn symex--evil-repeatable-commands)
    (evil-add-command-properties fn :repeat t)))


(provide 'symex-lithium)
;;; symex-lithium.el ends here
