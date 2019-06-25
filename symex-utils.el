;;; symex-utils.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

;; URL: https://github.com/countvajhula/symex-mode
;; Version: 0.1
;; Package-Requires: ((emacs "24.4") (cl-lib "0.6.1") (lispy "0.26.0") (paredit "24") (evil-cleverparens "20170718.413") (dash-functional "2.15.0") (evil "20180914.1216") (smartparens "20181007.1501") (racket-mode "20181030.1345") (geiser "0.10") (evil-surround "20180102.1401"))

;; This program is "part of the world," in the sense described at
;; http://drym.org.  From your perspective, this is no different than
;; MIT or BSD or other such "liberal" licenses that you may be
;; familiar with, that is to say, you are free to do whatever you like
;; with this program.  It is much more than BSD or MIT, however, in
;; that it isn't a license at all but an idea about the world and how
;; economic systems could be set up so that everyone wins.  Learn more
;; at drym.org.

;;; Commentary:
;;
;; Generic utilities used by symex mode
;;

;;; Code:


(defun current-line-empty-p ()
  "Check if the current line is empty.

From: https://emacs.stackexchange.com/a/16793"
  (save-excursion
    (beginning-of-line)
    (looking-at "[[:space:]]*$")))

(defun point-at-indentation-p ()
  "Check if point is at the point of indentation.

Point of indentation is the first non-whitespace character.
From: https://stackoverflow.com/a/13313091"
  (= (save-excursion (back-to-indentation)
                     (point))
     (point)))

;;; `with-undo-collapse` macro, to treat a sequence of operations
;;; as a single entry in the undo list.
;;; From: https://emacs.stackexchange.com/questions/7558/collapsing-undo-history/7560#7560
(defun undo-collapse-begin (marker)
  "Mark the beginning of a collapsible undo block.

This must be followed with a call to undo-collapse-end with a marker
eq to this one.

MARKER is some kind of delimiter for the undo block, TODO."
  (push marker buffer-undo-list))

(defun undo-collapse-end (marker)
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

(defmacro with-undo-collapse (&rest body)
  "Execute BODY, then collapse any resulting undo boundaries."
  (declare (indent 0))
  (let ((marker (list 'apply 'identity nil)) ; build a fresh list
        (buffer-var (make-symbol "buffer")))
    `(let ((,buffer-var (current-buffer)))
       (unwind-protect
           (progn
             (undo-collapse-begin ',marker)
             ,@body)
         (with-current-buffer ,buffer-var
           (undo-collapse-end ',marker))))))


(provide 'symex-utils)
;;; symex-utils.el ends here