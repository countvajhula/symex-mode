;;; symex-transformations.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

;; URL: https://github.com/countvajhula/symex.el

;; This program is "part of the world," in the sense described at
;; http://drym.org.  From your perspective, this is no different than
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
;;
;; Standard mutative operations to be performed on symexes.
;;

;;; Code:


(require 'paredit)
(require 'lispy)
(require 'evil)
(require 'evil-surround)
(require 'evil-cleverparens)  ;; really only need cp-textobjects here
(require 'symex-primitives)
(require 'symex-utils)
(require 'symex-misc)
(require 'symex-traversals)
(require 'symex-interop)

;;;;;;;;;;;;;;;;;;;;;;;
;;; TRANSFORMATIONS ;;;
;;;;;;;;;;;;;;;;;;;;;;;

(defun symex--do-while-traversing (operation traversal)
  "Traverse a symex using TRAVERSAL and do OPERATION at each step."
  (let ((result (symex-execute-traversal traversal
                                         nil
                                         operation)))
    (message "%s" result)
    (when result
      (symex--do-while-traversing operation
                                  traversal))))

(defun symex-eval-recursive ()
  "Evaluate a symex recursively.

Eval starting at the leaves and proceed down to the root, similarly
to how the Lisp interpreter does it (when it is following
'applicative-order evaluation')."
  (interactive)
  (save-excursion
    (symex-execute-traversal (symex-traversal
                              (circuit symex--traversal-preorder-in-tree)))
    ;; do it once first since it will be executed as a side-effect
    ;; _after_ each step in the traversal
    (symex-evaluate)
    (symex--do-while-traversing #'symex-evaluate
                                symex--traversal-postorder-in-tree)))

(defun symex-delete (count)
  "Delete COUNT symexes."
  (interactive "p")
  (let ((start (point))
        (end (symex--get-end-point count)))
    (kill-region start end))
  (cond ((symex--current-line-empty-p)             ; ^<>$
         (delete-region (line-beginning-position)
                        (if (eobp)
                            (line-end-position)
                          (1+ (line-end-position)))))
        ((save-excursion (back-to-indentation)     ; ^<>)
                         (forward-char)
                         (lispy-right-p))
         ;; Cases 2 and 3 in issue #18
         ;; if the deleted symex is preceded by a comment line
         ;; or if the preceding symex is followed by a comment
         ;; on the same line, then don't attempt to join lines
         (let ((original-position (point)))
           (when (symex--go-backward)
             (let ((previous-symex-pos (point))
                   (line-diff 1))
               (goto-char original-position)
               (if (catch 'stop
                     (forward-line -1)
                     (while (not (= (line-number-at-pos)
                                    (line-number-at-pos previous-symex-pos)))
                       (unless (symex--current-line-empty-p)
                         (if (symex-comment-line-p)
                             (throw 'stop nil)
                           (throw 'stop t)))
                       (forward-line -1)
                       (setq line-diff (- (line-number-at-pos original-position)
                                          (line-number-at-pos))))
                     t)
                   (progn (goto-char previous-symex-pos)
                          ;; ensure that there isn't a comment on the
                          ;; current line before joining lines
                          (unless (condition-case nil
                                      (progn (evil-find-char 1 ?\;)
                                             t)
                                    (error nil))
                              (dotimes (_ line-diff)
                                (symex--join-lines))))
                 (goto-char previous-symex-pos))))))
        ((save-excursion (evil-last-non-blank)  ; (<>$
                         (lispy-left-p))
         (symex--go-forward-to-start)
         (save-excursion
           (symex--join-lines t)))
        ((looking-at-p "\n")  ; (abc <>
         (evil-join (line-beginning-position)
                    (line-end-position)))
        ((save-excursion (forward-char)  ; ... <>)
                         (lispy-right-p))
         (symex--go-backward))
        (t (fixup-whitespace)))
  (symex-select-nearest)
  (symex-tidy))

(defun symex-change (count)
  "Change COUNT symexes."
  (interactive "p")
  (let ((start (point))
        (end (symex--get-end-point count)))
    (kill-region start end))
  (symex-enter-lowest))

(defun symex--clear ()
  "Helper to clear contents of symex."
  (cond ((symex-opening-round-p)
         (apply #'evil-delete (evil-inner-paren)))
        ((symex-opening-square-p)
         (apply #'evil-delete (evil-inner-bracket)))
        ((symex-opening-curly-p)
         (apply #'evil-delete (evil-inner-curly)))
        ((symex-string-p)
         (apply #'evil-delete (evil-inner-double-quote)))
        (t (kill-sexp))))

(defun symex-replace ()
  "Replace contents of symex."
  (interactive)
  (symex--clear)
  (when (or (symex-form-p) (symex-string-p))
    (forward-char))
  (symex-enter-lowest))

(defun symex-clear ()
  "Clear contents of symex."
  (interactive)
  (symex--clear)
  (symex-select-nearest)
  (symex-tidy))

(defun symex--emit-backward ()
  "Emit backward."
  (when (and (lispy-left-p)
             (not (symex-empty-list-p)))
    (save-excursion
      (symex--go-up)  ; need to be inside the symex to emit and capture
      (paredit-backward-barf-sexp 1))
    (symex--go-forward)
    (when (symex-empty-list-p)
      (fixup-whitespace)
      (re-search-forward lispy-left)
      (symex--go-down))))

(defun symex-emit-backward (count)
  "Emit backward, COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex--emit-backward)))

(defun symex--emit-forward ()
  "Emit forward."
  (when (and (lispy-left-p)
             (not (symex-empty-list-p)))
    (save-excursion
      (symex--go-up)  ; need to be inside the symex to emit and capture
      (paredit-forward-barf-sexp 1))
    (when (symex-empty-list-p)
      (symex--go-forward)
      (fixup-whitespace)
      (re-search-backward lispy-left))))

(defun symex-emit-forward (count)
  "Emit forward, COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex--emit-forward)))

(defun symex--capture-backward ()
  "Capture from behind."
  (when (lispy-left-p)
    (if (symex-empty-list-p)
        (forward-char)
      (symex--go-up))  ; need to be inside the symex to emit and capture
    (paredit-backward-slurp-sexp 1)
    (fixup-whitespace)
    (symex--go-down)))

(defun symex-capture-backward (count)
  "Capture from behind, COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex--capture-backward)))

(defun symex--capture-forward ()
  "Capture from the front."
  (when (lispy-left-p)
    (save-excursion
      (if (symex-empty-list-p)
          (forward-char)
        (symex--go-up))  ; need to be inside the symex to emit and capture
      (lispy-forward-slurp-sexp 1))))

(defun symex-capture-forward (count)
  "Capture from the front, COUNT times."
  (interactive "p")
  (dotimes (_ count)
    (symex--capture-forward)))

(defun symex--join ()
  "Merge symexes at the same level."
  (save-excursion
    (symex--go-forward)
    (paredit-join-sexps)))

(defun symex-join (count)
  "Merge COUNT symexes at the same level."
  (interactive "p")
  (dotimes (_ count)
    (symex--join)))

(defun symex-join-lines (count)
  "Join COUNT lines inside symex."
  (interactive "p")
  (dotimes (_ count)
    (symex--join-lines)))

(defun symex-join-lines-backwards (count)
  "Join COUNT lines backwards inside symex."
  (interactive "p")
  (dotimes (_ count)
    (symex--join-lines t)))

(defun symex--join-lines (&optional backwards)
  "Join lines inside symex.

If BACKWARDS is true, then joins current symex to previous one, otherwise,
by default, joins next symex to current one."
  (let ((original-column (current-column)))
    (if backwards
        (progn (evil-previous-line)
               (if (symex--current-line-empty-p)
                   (evil-join (line-beginning-position)
                              (1+ (line-beginning-position)))
                 (evil-join (line-beginning-position)
                            (line-end-position))))
      (save-excursion (forward-sexp)
                      (evil-join (line-beginning-position)
                                 (line-end-position))))
    (unless (= (current-column)
               original-column)
      (forward-char)))
  (symex-tidy))

(defun symex-yank (count)
  "Yank (copy) COUNT symexes."
  (interactive "p")
  (let ((start (point))
        (end (symex--get-end-point count)))
    (copy-region-as-kill start end)))

(defun symex--paste-before ()
  "Paste before symex."
  (interactive)
  (let ((extra-to-append
         (cond ((or (and (symex--point-at-indentation-p)
                         (not (bolp)))
                    (save-excursion (forward-sexp)
                                    (eolp)))
                "\n")
               (t " "))))
    (save-excursion
      (save-excursion
        (evil-paste-before nil nil)
        (when evil-move-cursor-back
          (forward-char))
        (insert extra-to-append))
      (symex--go-forward)
      (symex-tidy))))

(defun symex-paste-before (count)
  "Paste before symex, COUNT times."
  (interactive "p")
  (setq this-command 'evil-paste-before)
  (symex--with-undo-collapse
    (dotimes (_ count)
      (symex--paste-before))))

(defun symex--paste-after ()
  "Paste after symex."
  (interactive)
  (let ((extra-to-prepend
         (cond ((or (and (symex--point-at-indentation-p)
                         (not (bolp)))
                    (save-excursion (forward-sexp)
                                    (eolp)))
                "\n")
               (t " "))))
    (save-excursion
      (save-excursion
        (forward-sexp)
        (insert extra-to-prepend)
        (evil-paste-before nil nil)
        (forward-char))
      (symex--go-forward)
      (symex-tidy))
    (symex--go-forward)))

(defun symex-paste-after (count)
  "Paste after symex, COUNT times."
  (interactive "p")
  (setq this-command 'evil-paste-after)
  (symex--with-undo-collapse
    (dotimes (_ count)
      (symex--paste-after))))

(defun symex-open-line-after ()
  "Open new line after symex."
  (interactive)
  (forward-sexp)
  (newline-and-indent)
  (symex-enter-lowest))

(defun symex-open-line-before ()
  "Open new line before symex."
  (interactive)
  (newline-and-indent)
  (evil-previous-line)
  (indent-according-to-mode)
  (evil-move-end-of-line)
  (unless (or (symex--current-line-empty-p)
              (save-excursion (backward-char)
                              (lispy-left-p)))
    (insert " "))
  (symex-enter-lowest))

(defun symex-append-after ()
  "Append after symex (instead of vim's default of line)."
  (interactive)
  (forward-sexp)  ; selected symexes will have the cursor on the starting paren
  (symex-enter-lowest))

(defun symex-insert-before ()
  "Insert before symex (instead of vim's default at the start of line)."
  (interactive)
  (symex-enter-lowest))

(defun symex-insert-at-beginning ()
  "Insert at beginning of symex."
  (interactive)
  (if (lispy-left-p)
      (progn (forward-char)
             (symex-enter-lowest))
    (symex-enter-lowest)))

(defun symex-insert-at-end ()
  "Insert at end of symex."
  (interactive)
  (if (lispy-left-p)
      (progn (forward-sexp)
             (backward-char)
             (symex-enter-lowest))
    (progn (forward-sexp)
           (symex-enter-lowest))))

(defun symex-create (type)
  "Create new symex (list).

New list delimiters are determined by the TYPE."
  (save-excursion
    (cond ((equal type 'round)
           (insert "()"))
          ((equal type 'square)
           (insert "[]"))
          ((equal type 'curly)
           (insert "{}"))
          ((equal type 'angled)
           (insert "<>")))))

(defun symex-create-round ()
  "Create new symex with round delimiters."
  (interactive)
  (symex-create 'round))

(defun symex-create-square ()
  "Create new symex with square delimiters."
  (interactive)
  (symex-create 'square))

(defun symex-create-curly ()
  "Create new symex with curly delimiters."
  (interactive)
  (symex-create 'curly))

(defun symex-create-angled ()
  "Create new symex with angled delimiters."
  (interactive)
  (symex-create 'angled))

(defun symex-insert-newline (count)
  "Insert COUNT newlines before symex."
  (interactive "p")
  (newline-and-indent count)
  (symex-tidy))

(defun symex-append-newline (count)
  "Append COUNT newlines after symex."
  (interactive "p")
  (save-excursion
    (forward-sexp)
    (newline-and-indent count)
    (symex-tidy)))

(defun symex-swallow ()
  "Swallow symex.

This consumes the head of the symex, putting the rest of its contents
in the parent symex."
  (interactive)
  (symex--go-up)
  (symex--go-forward)
  (paredit-splice-sexp-killing-backward))

(defun symex-swallow-tail ()
  "Swallow-tail symex.

This consumes the tail of the symex, putting the head
in the parent symex."
  (interactive)
  (symex--go-up)
  (symex--go-forward)
  (paredit-splice-sexp-killing-forward)
  (symex--go-backward)
  (symex-tidy))

(defun symex-splice ()
  "Splice or 'clip' symex.

If the symex is a nested list, this operation eliminates the symex,
putting its contents in the parent symex.  If the symex is an atom,
then no action is taken."
  (interactive)
  (when (lispy-left-p)
    (symex--go-up)
    (paredit-splice-sexp-killing-backward)))

(defun symex-wrap-round ()
  "Wrap with ()."
  (interactive)
  (paredit-wrap-round)
  (symex--go-down))

(defun symex-wrap-square ()
  "Wrap with []."
  (interactive)
  (paredit-wrap-square)
  (symex--go-down))

(defun symex-wrap-curly ()
  "Wrap with {}."
  (interactive)
  (paredit-wrap-curly)
  (evil-find-char-backward nil 123))

(defun symex-wrap-angled ()
  "Wrap with <>."
  (interactive)
  (paredit-wrap-angled)
  (evil-find-char-backward nil 60))

(defun symex-wrap ()
  "Wrap with containing symex."
  (interactive)
  (symex-wrap-round)
  (symex-insert-at-beginning))

(defun symex--shift-forward ()
  "Move symex forward in current tree level."
  (forward-sexp)
  (condition-case nil
      (progn (transpose-sexps 1)
             (backward-sexp))
    (error (backward-sexp))))

(defun symex-shift-forward (count)
  "Move symex forward COUNT times in current tree level."
  (interactive "p")
  (dotimes (_ count)
    (symex--shift-forward)))

(defun symex--shift-backward ()
  "Move symex backward in current tree level."
  (let ((move (symex--go-backward)))
    (when move
      (symex--shift-forward)
      (symex--go-backward))))

(defun symex-shift-backward (count)
  "Move symex backward COUNT times in current tree level."
  (interactive "p")
  (dotimes (_ count) (symex--shift-backward)))

(defun symex-change-delimiter ()
  "Change delimiter enclosing current symex, e.g. round -> square brackets."
  (interactive)
  (evil-surround-change (following-char)))

(defun symex-comment ()
  "Comment out symex."
  (interactive)
  (mark-sexp)
  (comment-dwim nil))

(defun symex-tidy ()
  "Auto-indent symex and fix any whitespace."
  (interactive)
  (fixup-whitespace)
  (when (save-excursion (looking-at-p "[[:space:]]"))
      (forward-char))
  (condition-case nil
      (save-excursion
        (forward-sexp)
        (fixup-whitespace))
    (error nil))
  (condition-case err
      (save-excursion
        (apply #'evil-indent
               (seq-take (evil-cp-a-form 1)
                         2)))
    (error (message "[Symex] symex-tidy: suppressed error %S" err)
           (let ((start (point))
                 (end (save-excursion (forward-sexp) (point))))
             ;; maybe we should just always use this instead
             (save-excursion
               (apply #'evil-indent
                      (list start end))))))
  (symex-select-nearest))

(defun symex-tidy-proper ()
  "Properly tidy things up."
  (interactive)
  (save-excursion
    (symex-execute-traversal
     (symex-traversal (circuit symex--traversal-preorder-in-tree)))
    ;; do it once first since it will be executed as a side-effect
    ;; _after_ each step in the traversal
    (symex-tidy)
    (symex--do-while-traversing #'symex-tidy
                                symex--traversal-postorder-in-tree)))

(defun symex-collapse ()
  "Collapse a symex to a single line."
  (interactive)
  (save-excursion
    (let ((start (point)))
      (symex-execute-traversal
       (symex-traversal (circuit symex--traversal-preorder-in-tree)))
      ;; do it once first since it will be executed as a side-effect
      ;; _after_ each step in the traversal
      (symex--join-lines t)
      (symex--do-while-traversing
       (apply-partially #'symex--join-lines t)
       (symex-traversal
        (precaution symex--traversal-postorder-in-tree
                    (afterwards (lambda ()
                                  (not (equal (line-number-at-pos (point))
                                              (line-number-at-pos start)))))))))))

(provide 'symex-transformations)
;;; symex-transformations.el ends here
