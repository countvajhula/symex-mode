;;; symex-hydra.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Hydra modal frontend to symex.

;;; Code:

(require 'hydra)
(require 'evil)

(require 'symex-ui)
(require 'symex-misc)
(require 'symex-transformations)
(require 'symex-interop)

;; to avoid byte compile warnings.  eventually sort out the dependency
;; order so this is unnecessary
(defvar chimera-symex-mode)
(declare-function chimera-hydra-portend-exit "ext:ignore")

(defun symex-hydra-exit ()
  "Take necessary action upon symex mode exit."
  (symex-exit-mode)
  (when (and (boundp 'rigpa-mode) rigpa-mode)
    (chimera-hydra-portend-exit chimera-symex-mode t)))

(defun symex-hide-menu ()
  "Hide symex menu."
  (hydra-set-property 'hydra-symex :verbosity 0))

(defun symex-show-menu ()
  "Show symex menu."
  (hydra-set-property 'hydra-symex :verbosity 2))

(defun symex-toggle-menu ()
  "Show/hide the symex menu.

Note that hiding the menu still retains the symex editing mode,
and simply toggles whether the menu is visible or not.  To enter
and exit the symex modal interface, use `symex-mode-interface`
to enter, and any of the standard exits to exit."
  (interactive)
  (let ((visibility (hydra-get-property 'hydra-symex :verbosity)))
    (if (> visibility 0)
        (symex-hide-menu)
      (symex-show-menu))))

;; TODO: it might make sense to symex-tidy as a formal followup,
;; possibly after every head, but at least after the transformations
;; likewise, we might want to disable and re-enable highlighting,
;; if active, on each command
(defhydra hydra-symex (:columns 4
                       :post (symex-hydra-exit)
                       :after-exit (symex--signal-exit))
  "Symex mode."
  ("(" symex-create-round "()")
  ("[" symex-create-square "[]")
  ("{" symex-create-curly "{}")
  ("<" symex-create-angled "<>")
  ("h" symex-go-backward "previous")
  ("k" symex-go-up "up")
  ("j" symex-go-down "down")
  ("l" symex-go-forward "next")
  ("gj" symex-next-visual-line "down (line)")
  ("gk" symex-previous-visual-line "up (line)")
  ("f" symex-traverse-forward "flow forward")
  ("b" symex-traverse-backward "flow backward")
  ("C-f" symex-traverse-forward-more "flow forward more")
  ("C-b" symex-traverse-backward-more "flow backward more")
  ("F" symex-traverse-forward-skip "skip forward")
  ("B" symex-traverse-backward-skip "skip backward")
  ("C-h" symex-leap-backward "leap backward")
  ("C-l" symex-leap-forward "leap forward")
  ("C-M-h" symex-soar-backward "soar backward")
  ("C-M-l" symex-soar-forward "soar forward")
  ("C-k" symex-climb-branch "climb branch")
  ("C-j" symex-descend-branch "descend branch")
  ("y" symex-yank "yank (copy)")
  ("Y" symex-yank-remaining "yank remaining")
  ("p" symex-paste-after "paste after")
  ("P" symex-paste-before "paste before")
  ("x" symex-delete "delete")
  ("X" symex-delete-backwards "delete backwards")
  ("D" symex-delete-remaining "delete remaining")
  ("c" symex-change "change" :exit t)
  ("C" symex-change-remaining "change remaining" :exit t)
  ("C--" symex-clear "clear")
  ("s" symex-replace "replace" :exit t)
  ("S" symex-change-delimiter "change surrounding delimiter")
  ("H" symex-shift-backward "move backward")
  ("L" symex-shift-forward "move forward")
  ("M-H" symex-shift-backward-most "move most backward")
  ("M-L" symex-shift-forward-most "move most forward")
  ("K" paredit-raise-sexp "raise")
  ("C-S-j" symex-emit-backward "emit backward")
  ("C-(" symex-capture-backward "capture backward")
  ("C-S-h" symex-capture-backward "capture backward")
  ("C-{" symex-emit-backward "emit backward")
  ("C-S-l" symex-capture-forward "capture forward")
  ("C-}" symex-emit-forward "emit forward")
  ("C-S-k" symex-emit-forward "emit forward")
  ("C-)" symex-capture-forward "capture forward")
  ("z" symex-swallow "swallow head")
  ("Z" symex-swallow-tail "swallow tail")
  ("e" symex-evaluate "evaluate")
  ("E" symex-evaluate-remaining "evaluate remaining")
  ("C-M-e" symex-evaluate-pretty "pretty evaluate")
  ("d" symex-evaluate-definition "evaluate definition")
  ("M-e" symex-eval-recursive "evaluate recursively")
  ("T" symex-evaluate-thunk "evaluate as 'thunk'")
  (":" eval-expression "eval expression")
  ("t" symex-switch-to-scratch-buffer "scratch buffer" :exit t)
  ("M" symex-switch-to-messages-buffer "messages buffer")
  ("r" symex-repl "go to REPL" :exit t)
  ("R" symex-run "run buffer")
  ("|" symex-split "split")
  ("&" symex-join "merge (join)")
  ("-" symex-splice "clip/splice")
  (")" symex-wrap-round "wrap with ()")
  ("]" symex-wrap-square "wrap with []")
  ("}" symex-wrap-curly "wrap with {}")
  (">" symex-wrap-angled "wrap with <>")
  ("C-'" symex-cycle-quote "cycle quoting prefix")
  ("C-," symex-cycle-unquote "cycle unquoting prefix")
  ("`" symex-add-quoting-level "add quoting level")
  ("C-`" symex-remove-quoting-level "remove quoting level")
  ("o" symex-open-line-after "open line after" :exit t)
  ("O" symex-open-line-before "open line before" :exit t)
  ("n" symex-insert-newline "newline")
  ("C-S-o" symex-append-newline "append newline")
  ("J" symex-join-lines "join lines")
  ("M-J" symex-collapse "collapse to single line")
  ("M-<" symex-collapse "collapse to single line")
  ("M->" symex-unfurl "unfurl across lines")
  ("C-M-<" symex-collapse-remaining "collapse remaining")
  ("C-M->" symex-unfurl-remaining "unfurl remaining")
  ("N" symex-join-lines-backwards "join lines backwards")
  ("0" symex-goto-first "go to first")
  ("M-h" symex-goto-first "go to first")
  ("$" symex-goto-last "go to last")
  ("M-l" symex-goto-last "go to last")
  ("M-j" symex-goto-lowest "go to lowest")
  ("M-k" symex-goto-highest "go to highest")
  ("=" symex-tidy "tidy/indent")
  ("<tab>" symex-tidy "tidy/indent")
  ("C-=" symex-tidy-remaining "tidy remaining")
  ("C-<tab>" symex-tidy-remaining "tidy remaining")
  ("M-=" symex-tidy-proper "tidy/indent properly")
  ("M-<tab>" symex-tidy-proper "tidy/indent properly")
  ("A" symex-append-after "append after symex" :exit t)
  ("a" symex-insert-at-end "append inside symex" :exit t)
  ("i" symex-insert-at-beginning "insert inside symex" :exit t)
  ("I" symex-insert-before "insert before symex" :exit t)
  ("w" symex-wrap "wrap and insert" :exit t)
  ("W" symex-wrap-and-append "wrap and append" :exit t)
  ("g" evil-jump-to-tag "go to definition")
  ("G" evil-jump-backward "return to previous location")
  (";" symex-comment "comment out")
  ("M-;" symex-comment-remaining "comment out remaining")
  ("C-;" symex-eval-print "eval + print")
  ;; canonical action
  ("s-;" symex-evaluate "evaluate" :exit t)
  ;; configuration
  ("H-h" symex--toggle-highlight "toggle highlight")
  ("H-m" symex-toggle-menu "show/hide this menu")
  ;; explicit "pass through" so hydra persists
  ("u" undo-only nil)
  ("C-r" undo-redo nil)
  ("C-e" symex--scroll-down nil)
  ("C-y" symex--scroll-up nil)
  ;; standard exits
  ("?" symex-describe "info")
  ("<return>" symex-enter-lower "enter lower" :exit t)
  ("<escape>" symex-escape-higher "escape higher" :exit t)
  ("C-g" symex-escape-higher "escape higher" :exit t))

(defun symex-hydra-initialize ()
  "Initialize hydra modal interface."
  ;; just for symmetry - nothing specific to do here atm
  nil)


(provide 'symex-hydra)
;;; symex-hydra.el ends here
