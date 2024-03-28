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
  (forward-line -1)
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

(defun symex-lisp--paste (before after)
  "Paste before, padding on either side.

Paste text from the paste buffer, padding it with BEFORE and AFTER
text, on the respective side."
  (let* ((text-to-paste
          ;; add the padding to the yanked text
          (concat before
                  (symex--current-kill)
                  after))
         ;; remember initial point location
         (start (point)))
    (insert text-to-paste)
    (indent-region start (point))
    (buffer-substring start (point))))

(defun symex-lisp--padding (&optional before)
  "Determine paste padding needed for current point position."
  (let* ((after (not before))
         (island
          (and (bolp)
               (condition-case nil
                   (save-excursion (forward-sexp)
                                   (eolp))
                 (error nil))))
         (at-eob
          (condition-case nil
              (save-excursion (forward-sexp)
                              (eobp))
            (error nil)))
         (previous-line-empty
          (symex--previous-line-empty-p))
         (next-line-empty
          (symex--following-line-empty-p))
         (surrounding-lines-empty (and previous-line-empty
                                       next-line-empty))
         (paste-text-contains-newlines
          (seq-contains-p (symex--current-kill) ?\n))
         (at-eol (condition-case nil
                     (save-excursion (forward-sexp)
                                     (eolp))
                   (error nil)))
         (multiline (let ((original-line (line-number-at-pos)))
                      (condition-case nil
                          (save-excursion (forward-sexp)
                                          (not (= original-line
                                                  (line-number-at-pos))))
                        (error nil)))))
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
               at-eol
               multiline)
           "\n")
          ((symex-inside-empty-form-p) "")
          (t " "))))

(defun symex-lisp--paste-before ()
  "Paste before symex."
  (interactive)
  (symex-lisp--paste ""
                     (symex-lisp--padding t)))

(defun symex-lisp-paste-before ()
  "Paste before symex."
  (symex--with-undo-collapse
    (let ((pasted-text (symex-lisp--paste-before)))
      (save-excursion
        (let* ((end (point))
               (start (- end (length pasted-text)))
               (end-line (line-number-at-pos end)))
          ;; we use end + 1 here since end is the point
          ;; right before the initial expression, which
          ;; won't be indented as it thus would fall
          ;; outside the region to be indented.
          (indent-region start (1+ end))
          ;; indenting may add characters (e.g. spaces)
          ;; to the buffer, so we rely on the line number
          ;; instead.
          (symex--goto-line end-line)
          ;; if the last line has any trailing forms,
          ;; indent them.
          (symex--same-line-tidy-affected)
          (not (equal pasted-text "")))))))

(defun symex-lisp--paste-after ()
  "Paste after symex.

If a symex is currently selected, then paste after the end of the
selected expression. Otherwise, paste in place."
  (interactive)
  (let ((padding (symex-lisp--padding nil)))
    (save-excursion
      (condition-case nil
          (forward-sexp)
        (error nil))
      (symex-lisp--paste padding
                         ""))))

(defun symex-lisp-paste-after ()
  "Paste after symex."
  (symex--with-undo-collapse
    (let ((selected (symex-lisp--selected-p))
          (pasted-text (symex-lisp--paste-after)))
      (save-excursion
        (when selected
          ;; if it was (|), then we are already at the start
          ;; of the pasted text
          (forward-sexp)) ; go to beginning of pasted text
        (let* ((start (point))
               (end (+ start
                       (length pasted-text))))
          (goto-char end)
          (symex--same-line-tidy-affected)))
      (not (equal pasted-text "")))))

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
