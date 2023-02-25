;;; symex-evil-support.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Supporting utilites for the evil modal frontend.

;;; Code:

(require 'evil)


(defun symex--define-evil-key (key fn map)
  "Define a keybinding in the symex evil state.

Assigns FN to KEY in keymap MAP."
  (ignore key fn map)  ; keep the byte-compiler happy
  (evil-define-key* (list 'symex 'visual 'operator)
                    map
                    (kbd key)
                    fn))

(defun symex--define-evil-keys-from-spec (keyspec keymap)
  "Define evil keys from a specification.

Read the specification KEYSPEC and define the indicated keybindings in
the KEYMAP.  The specification of each keybinding is expected to be in
the form (key . fn)."
  (dolist (keybinding keyspec)
    (let ((key (car keybinding))
          (fn (cdr keybinding)))
      (symex--define-evil-key key fn keymap))))

(provide 'symex-evil-support)
;;; symex-evil-support.el ends here
