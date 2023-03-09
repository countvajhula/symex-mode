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

(defun symex--combine-alists (al1 al2)
  "Combine two association lists, prioritizing one of them.

The result includes all values present in either AL1 or AL2.  If a key
exists in both AL1 as well as AL2, the value in AL1 is retained in the
result."
  (let ((result al1))
    (dolist (p al2)
      (cl-pushnew p result :key #'car :test #'equal))
    result))

(defun symex--remaining-length ()
  "Compute the remaining length of the current symex.

This should be done via DSL computation semantics at some point."
  (symex-save-excursion
    (let ((result (symex-execute-traversal symex--traversal-goto-last)))
     (1+ (length result)))))


(provide 'symex-utils)
;;; symex-utils.el ends here
