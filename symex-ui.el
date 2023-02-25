;;; symex-ui.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; User interface-related resources

;;; Code:


(require 'symex-custom)

(defface symex--current-node-face
  '((t :inherit highlight :extend nil))
  "Face used to highlight the current tree node."
  :group 'symex-faces)

(defvar symex--current-overlay nil "The current overlay which highlights the current node.")

(defun symex--delete-overlay ()
  "Delete the highlight overlay."
  (when symex--current-overlay
    (delete-overlay symex--current-overlay)))

(defun symex--update-overlay ()
  "Update the highlight overlay to match the start/end position of NODE."
  (when symex--current-overlay
    (delete-overlay symex--current-overlay))
  (setq-local symex--current-overlay
              (make-overlay (symex--get-starting-point)
                            (symex--get-end-point 1)))
  (overlay-put symex--current-overlay 'face 'symex--current-node-face))

(defun symex--overlay-active-p ()
  "Is the overlay active?"
  (and symex--current-overlay
       (overlay-start symex--current-overlay)))

(defun symex--toggle-highlight ()
  "Toggle highlighting of selected symex."
  (interactive)
  (if (symex--overlay-active-p)
      (symex--delete-overlay)
    (symex--update-overlay))
  (setq symex-highlight-p
        (not symex-highlight-p)))


(provide 'symex-ui)
;;; symex-ui.el ends here
