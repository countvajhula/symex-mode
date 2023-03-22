;;; symex-transformations-lisp.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Standard mutative operations to be performed on Lisp symexes.

;;; Code:

(require 'cl-lib)

(require 'evil)
(require 'evil-surround)
(require 'symex-primitives)
(require 'symex-primitives-lisp)
(require 'symex-utils)
(require 'symex-traversals)
(require 'symex-interop)

;;;;;;;;;;;;;;;;;;;;;;;
;;; TRANSFORMATIONS ;;;
;;;;;;;;;;;;;;;;;;;;;;;

(defun symex-lisp-tidy (count)
  "Auto-indent symex and fix any whitespace."
  ;; fix leading whitespace
  (fixup-whitespace)
  ;; fixup may move point into the whitespace - restore it
  (when (looking-at-p "[[:space:]]")
    (symex-lisp--go-to-next-non-whitespace-char))
  ;; fix trailing whitespace (indent region doesn't)
  (condition-case nil
      (save-excursion
        (forward-sexp)
        (fixup-whitespace))
    (error nil))
  (let ((start (point))
        (end (save-excursion
               (dotimes (_ count)
                 (forward-sexp))
               (point))))
    (indent-region start end))
  (symex-lisp-select-nearest))

(defun symex-lisp-clear ()
  "Helper to clear contents of symex."
  (cond ((symex--go-up) (symex-delete-remaining))
        ((symex-string-p) (save-excursion (kill-sexp)
                                          (insert "\"\"")))
        ((or (symex-empty-list-p)
             (symex--special-empty-list-p))
         ;; nothing needs to be done
         nil)
        (t (kill-sexp))))

(defun symex-lisp-replace ()
  (symex-lisp-clear)
  (forward-char (symex--form-offset)))

(defun symex-lisp--delete (count)
  "Delete COUNT symexes."
  (let ((last-command nil)  ; see symex-yank re: last-command
        (start (point))
        (end (symex--get-end-point count)))
    (when (> end start)
      (kill-region start end)
      t)))

(defun symex-lisp-delete (count)
  "Delete COUNT symexes."
  (interactive "p")
  (let ((result (symex-lisp--delete count)))
    (cond ((symex--current-line-empty-p)         ; ^<>$
           ;; only join up to the next symex if the context suggests
           ;; that a line break is not desired
           (if (or (save-excursion (forward-line)
                                   (not (symex--current-line-empty-p)))
                   (save-excursion (forward-line -1)
                                   (symex--current-line-empty-p)))
               (symex--join-to-next)
             ;; don't leave an empty line where the symex was
             (delete-region (line-beginning-position)
                          (1+ (line-end-position)))))
        ((or (save-excursion (evil-last-non-blank) ; (<>$
                             (symex-left-p)))
         (symex--join-to-next))
        ((looking-at-p "\n")  ; (abc <>
         (if (save-excursion (forward-line)
                             (not (symex--current-line-empty-p)))
             ;; only join up to the next symex if the context suggests
             ;; that a line break is not desired
             (symex--join-to-next)
           (symex--go-backward)))
        ((save-excursion (back-to-indentation) ; ^<>)
                         (forward-char)
                         (symex-right-p))
         ;; Cases 2 and 3 in issue #18
         ;; if the deleted symex is preceded by a comment line
         ;; or if the preceding symex is followed by a comment
         ;; on the same line, then don't attempt to join lines
         (let ((original-position (point)))
           (when (symex--go-backward)
             (save-excursion
               (let ((previous-symex-end-pos (symex--get-end-point 1)))
                 (unless (symex--intervening-comment-line-p previous-symex-end-pos
                                                            original-position)
                   (goto-char previous-symex-end-pos)
                   ;; ensure that there isn't a comment on the
                   ;; preceding line before joining lines
                   (unless (condition-case nil
                               (save-excursion (evil-find-char 1 ?\;)
                                               t)
                             (error nil))
                     (symex--join-to-match symex--re-right)
                     (symex--adjust-point))))))))
        ((save-excursion (forward-char) ; ... <>)
                         (symex-right-p))
         (symex--go-backward))
        (t (symex--go-forward)))
    ;; should we return the actual motion we took?
    result))

(defun symex-lisp-delete-backwards (count)
  "Delete COUNT symexes backwards."
  (interactive "p")
  (dotimes (_ count)
    (when (symex--go-backward)
      (symex-lisp-delete 1))))

(defun symex-lisp-append-after ()
  "Append after symex (instead of vim's default of line)."
  (interactive)
  (forward-sexp)  ; selected symexes will have the cursor on the starting paren
  (insert " "))

(defun symex-lisp-open-line-after ()
  "Open new line after symex."
  (interactive)
  (forward-sexp)
  (if (symex-inline-comment-p)
      (progn (end-of-line)
             (newline-and-indent))
    (newline-and-indent)))

(defun symex-lisp-open-line-before ()
  "Open new line before symex."
  (interactive)
  (newline-and-indent)
  (evil-previous-line)
  (indent-according-to-mode)
  (evil-move-end-of-line)
  (unless (or (symex--current-line-empty-p)
              (save-excursion (backward-char)
                              (symex-left-p)))
    (insert " ")))

(defun symex-lisp-insert-before ()
  "Insert before symex (instead of vim's default at the start of line)."
  (interactive)
  (insert " ")
  (backward-char))

(defun symex-lisp-insert-at-beginning ()
  "Insert at beginning of symex."
  (interactive)
  (when (or (symex-left-p)
            (symex-string-p))
    (forward-char)))

(defun symex-lisp-insert-at-end ()
  "Insert at end of symex."
  (interactive)
  (if (or (symex-left-p)
          (symex-string-p))
      (progn (forward-sexp)
             (backward-char))
    (forward-sexp)))

(defun symex--emit-forward ()
  "Emit forward."
  (when (and (symex-left-p)
             (not (symex-empty-list-p)))
    (save-excursion
      (symex--go-up)  ; need to be inside the symex to emit and capture
      (paredit-forward-barf-sexp 1))
    (when (symex-empty-list-p)
      (symex--go-forward)
      (fixup-whitespace)
      (re-search-backward symex--re-left))))

(defun symex-lisp-emit-forward (count)
  "Emit forward."
  (dotimes (_ count)
    (symex--emit-forward)))

(defun symex-lisp--paste (before after)
  "Paste before, padding on either side.

Paste text from the paste buffer, padding it with BEFORE and AFTER
text, on the respective side."
  (save-excursion
    (let* ((text-to-paste
            ;; add the padding to the yanked text
            (concat before
                    (current-kill 0 t)
                    after))
           ;; remember initial point location
           (start (point)))
      (insert text-to-paste)
      (indent-region start (point))
      (buffer-substring start (point)))))

(defun symex-lisp--padding (&optional before)
  "Determine paste padding needed for current point position."
  (let* ((after (not before))
         (island
          (and (bolp)
               (save-excursion (forward-sexp)
                               (eolp))))
         (at-eob
          (save-excursion (forward-sexp)
                          (eobp)))
         (previous-line-empty
          (save-excursion (forward-line -1)
                          (symex--current-line-empty-p)))
         (next-line-empty
          (save-excursion (forward-sexp)
                          (forward-line)
                          (symex--current-line-empty-p)))
         (surrounding-lines-empty (and previous-line-empty
                                       next-line-empty))
         (paste-text-contains-newlines
          (seq-contains-p (current-kill 0 t) ?\n)))
    (cond ((and island
                ;; if we're at the toplevel, on an "island" symex
                ;; (i.e. with no peers occupying the same lines),
                (or (and after next-line-empty)
                    ;; and if the side we want to paste on already
                    ;; contains an empty line,
                    (and before previous-line-empty)
                    ;; or if we happen to be at the end of the buffer
                    ;; for pasting after, then check the opposite side
                    ;; instead for the clue on what's expected
                    (and at-eob previous-line-empty))
                ;; and if the text to be pasted contains newlines, or
                ;; if both surrounding lines are empty _and_ we aren't
                ;; at the first symex
                (or paste-text-contains-newlines
                    (and surrounding-lines-empty
                         (not (symex--point-at-first-symex-p)))))
                ;; then we typically want an extra newline separator
           "\n\n")
          ((or (symex--point-at-indentation-p)
               (let ((original-line (line-number-at-pos)))
                 (save-excursion (forward-sexp)
                                 (or (eolp)
                                     ;; for multi-line symex, add a newline
                                     (not (= original-line
                                             (line-number-at-pos)))))))
           "\n")
          (t " "))))

(defun symex-lisp--paste-before ()
  "Paste before symex."
  (interactive)
  (symex-lisp--paste ""
                     (symex-lisp--padding t)))

(defun symex-lisp-paste-before (count)
  (symex--with-undo-collapse
    (let ((pasted-text ""))
      (dotimes (_ count)
        (setq pasted-text
              (concat (symex-lisp--paste-before)
                      pasted-text)))
      (save-excursion
        (let* ((end (+ (point) (length pasted-text)))
               (end-line (line-number-at-pos end)))
          ;; we use end + 1 here since end is the point
          ;; right before the initial expression, which
          ;; won't be indented as it thus would fall
          ;; outside the region to be indented.
          (indent-region (point) (1+ end))
          ;; indenting may add characters (e.g. spaces)
          ;; to the buffer, so we rely on the line number
          ;; instead.
          (symex--goto-line end-line)
          ;; if the last line has any trailing forms,
          ;; indent them.
          (symex--same-line-tidy-affected))))))

(defun symex-lisp--paste-after ()
  "Paste after symex."
  (interactive)
  (let ((padding (symex-lisp--padding nil)))
    (save-excursion (forward-sexp)
                    (symex-lisp--paste padding
                                       ""))))

(defun symex-lisp-paste-after (count)
  "Paste after symex."
  (symex--with-undo-collapse
    (let ((pasted-text ""))
      (dotimes (_ count)
        (setq pasted-text
              (concat (symex-lisp--paste-after)
                      pasted-text)))
      (save-excursion
        (forward-sexp) ; go to beginning of pasted text
        (goto-char (+ (point)
                      (length pasted-text))) ; end of pasted text
        (symex--same-line-tidy-affected))
      ;; move to indicate appropriate posterior selection
      (forward-sexp)
      (forward-char))))

(defun symex-lisp-yank (count)
  "Yank (copy) COUNT symexes."
  (interactive "p")
  ;; we set `last-command` here to avoid appending to the kill ring
  ;; when it's a delete followed by a yank. We want to treat each as
  ;; independent entries in the kill ring
  (let ((last-command nil))
    (let ((start (point))
          (end (symex--get-end-point count)))
      (copy-region-as-kill start end))))

(provide 'symex-transformations-lisp)
;;; symex-transformations-lisp.el ends here
