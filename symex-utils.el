;;; symex-utils.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Generic utilities used by symex mode

;;; Code:

(require 'cl-lib)
(require 'symex-primitives)

(defun symex--current-line-empty-p ()
  "Check if the current line is empty.

From: https://emacs.stackexchange.com/a/16793"
  (save-excursion
    (beginning-of-line)
    (looking-at "[[:space:]]*$")))

(defun symex--next-line-empty-p ()
  "Check if the next line is empty."
  (save-excursion (forward-line)
                  (symex--current-line-empty-p)))

(defun symex--previous-line-empty-p ()
  "Check if the previous line is empty."
  (save-excursion (forward-line -1)
                  (symex--current-line-empty-p)))

(defun symex--point-at-indentation-p ()
  "Check if point is at the point of indentation.

Point of indentation is the first non-whitespace character.
From: https://stackoverflow.com/a/13313091"
  (= (save-excursion (back-to-indentation)
                     (point))
     (point)))

(defun symex--point-on-last-line-p ()
  "Check if point is on the last line of the buffer."
  (= (line-number-at-pos)
     (save-excursion (goto-char (point-max))
                     (line-number-at-pos))))

(defun symex--goto-line (line-no)
  "Go to line number LINE-NO.

Emacs docs recommend against using `goto-line`, suggesting
the following recipe instead."
  (goto-char (point-min))
  (forward-line (1- line-no)))

(defvar symex--re-non-whitespace "[^[:space:]\n]"
  "A non-whitespace character.")

(defvar symex--re-non-whitespace-or-newline "[^[:space:]]"
  "A non-whitespace character.")

(defun symex--go-to-next-non-whitespace-char ()
  "Move point to the next non-whitespace character.

If the current character is non-whitespace, point is not moved."
  (unless (looking-at-p symex--re-non-whitespace)
    (condition-case nil
        (progn (re-search-forward symex--re-non-whitespace)
               ;; since the re search goes to the end of the match
               (backward-char)
               t)
      (error nil))))

(defun symex--join-to-match (pattern)
  "Join current position to the next position matching PATTERN.

This eliminates whitespace between the original position and the found
match."
  (condition-case nil
      (let* ((start (point))
             (end (save-excursion (re-search-forward pattern)
                                  (match-beginning 0))))
        (delete-region start end))))

(defun symex--join-to-non-whitespace ()
  "Join current position to the next non-whitespace character.

This eliminates whitespace between the original position and the found
match."
  (symex--join-to-match symex--re-non-whitespace))

(defun symex--join-to-non-whitespace-or-newline ()
  "Join current position to the next non-whitespace character.

This eliminates whitespace between the original position and the found
match."
  (symex--join-to-match symex--re-non-whitespace-or-newline))

;; `with-undo-collapse` macro, to treat a sequence of operations
;; as a single entry in the undo list.
;; From: https://emacs.stackexchange.com/questions/7558/collapsing-undo-history/7560#7560
(defun symex--undo-collapse-begin (marker)
  "Mark the beginning of a collapsible undo block.

This must be followed with a call to ‘symex--undo-collapse-end’ with a marker
eq to this one.

MARKER is some kind of delimiter for the undo block, TODO."
  (push marker buffer-undo-list))

(defun symex--undo-collapse-end (marker)
  "Collapse undo history until a matching marker.

MARKER is some kind of delimiter for the undo block, TODO."
  (cond
   ((eq (car buffer-undo-list) marker)
    (setq buffer-undo-list (cdr buffer-undo-list)))
   (t
    (let ((l buffer-undo-list))
      (while (not (eq (cadr l) marker))
        (cond
         ((null (cdr l))
          (error "Encountered undo-collapse-end with no matching marker"))
         ((eq (cadr l) nil)
          (setf (cdr l) (cddr l)))
         (t (setq l (cdr l)))))
      ;; remove the marker
      (setf (cdr l) (cddr l))))))

(defmacro symex--with-undo-collapse (&rest body)
  "Execute BODY, then collapse any resulting undo boundaries."
  (declare (indent 0))
  (let ((marker (list 'apply 'identity nil)) ; build a fresh list
        (buffer-var (make-symbol "buffer")))
    `(let ((,buffer-var (current-buffer)))
       (unwind-protect
           (progn
             (symex--undo-collapse-begin ',marker)
             ,@body)
         (with-current-buffer ,buffer-var
           (symex--undo-collapse-end ',marker))))))

;; Modified from: https://stackoverflow.com/a/24283996
;; In cases where we mutate the buffer within a save-excursion
;; (e.g. by using symex--tidy), it seems that save-excursion
;; does not return to the original point even if the mutation
;; did not actually result in any changes. Instead, it seems
;; to return to the beginning of the changed region, which
;; for our purposes is sometimes one character before the
;; original position. We use this simple macro to restore point
;; to its exact original location.
(defmacro symex--save-point-excursion (&rest forms)
  (declare (indent 0))
  (let ((old-point (gensym "old-point")))
    `(let ((,old-point (point)))
       (prog1
           (progn ,@forms)
         (goto-char ,old-point)))))

(defun symex--combine-alists (al1 al2)
  "Combine two association lists, prioritizing one of them.

The result includes all values present in either AL1 or AL2.  If a key
exists in both AL1 as well as AL2, the value in AL1 is retained in the
result."
  (let ((result al1))
    (dolist (p al2)
      (cl-pushnew p result :key #'car :test #'equal))
    result))

(defun symex--delete-whole-line ()
  "Delete entire current line.

Similar to `kill-whole-line` but doesn't add an entry to the kill
ring."
  (delete-region (line-beginning-position)
                 (line-end-position))
  (unless (eobp)
    (delete-char 1)))

(defun symex--current-kill ()
  "Get current kill ring entry without rotating the kill ring."
  (current-kill 0 t))

(defun symex--kill-ring-push (entry)
  "Push an ENTRY onto the kill ring."
  (kill-new entry))

(defun symex--kill-ring-pop ()
  "Pop the latest entry off the kill ring."
  (let ((result (pop kill-ring)))
    (setq kill-ring-yank-pointer kill-ring)
    result))

(defun symex--kill-ring-compose ()
  "Compose kill ring entries.

This concatenates the latest kill with the preceding one, treating the
preceding one as the accumulator. "
  (let ((latest (symex--kill-ring-pop)))
    (kill-append latest nil)))

(defun symex--fix-leading-whitespace ()
  "Fix leading whitespace."
  ;; fix leading whitespace
  (fixup-whitespace)
  ;; fixup may move point into the whitespace - restore it
  (when (looking-at-p "[[:space:]]")
    (symex--go-to-next-non-whitespace-char)))

(defun symex--fix-trailing-whitespace (count)
  "Fix trailing whitespace."
  (condition-case nil
      (save-excursion
        (symex-select-end count)
        (fixup-whitespace))
    (error nil)))


(provide 'symex-utils)
;;; symex-utils.el ends here
