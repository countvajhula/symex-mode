
;;; Utilities for development and testing

;; Symex-TS hydra: useful for debugging Tree Sitter movements outside
;; of the rest of Symex.

(defface symex-ts-current-node-face
  '((t :inherit highlight :extend nil))
  "Face used to highlight the current tree node."
  :group 'symex-faces)

(defvar symex-ts--current-overlay nil "The current overlay which highlights the current node.")

(defun symex-ts--delete-overlay ()
  "Delete the highlight overlay."
  (when symex-ts--current-overlay
    (delete-overlay symex-ts--current-overlay)))

(defun symex-ts--update-overlay (node)
  "Update the highlight overlay to match the start/end position of NODE."
  (when symex-ts--current-overlay
    (delete-overlay symex-ts--current-overlay))
  (setq-local symex-ts--current-overlay (make-overlay (tsc-node-start-position node) (tsc-node-end-position node)))
  (overlay-put symex-ts--current-overlay 'face 'symex-ts-current-node-face))

(defun symex-ts--hydra-exit ()
  "Handle Hydra exit."
  (symex-ts--delete-overlay))

(defun symex-ts--move-next ()
  "Move to next sibling."
  (interactive)
  (symex-ts-move-next-sibling)
  (symex-ts--update-overlay symex-ts--current-node))

(defun symex-ts--move-previous ()
  "Move to previous sibling."
  (interactive)
  (symex-ts-move-prev-sibling)
  (symex-ts--update-overlay symex-ts--current-node))

(defun symex-ts--move-parent ()
  "Move to previous sibling."
  (interactive)
  (symex-ts-move-parent)
  (symex-ts--update-overlay symex-ts--current-node))

(defun symex-ts--move-child ()
  "Move to previous sibling."
  (interactive)
  (symex-ts-move-child)
  (symex-ts--update-overlay symex-ts--current-node))

(defhydra hydra-symex-ts (:post (symex-ts--hydra-exit))
  "Symex-TS."
  ("d" symex-ts-current-node-sexp "DEBUG NODE")

  ("h" symex-ts--move-previous "prev")
  ("l" symex-ts--move-next "next")
  ("j" symex-ts--move-parent "parent")
  ("k" symex-ts--move-child "child"))

(defun symex-ts-launch ()
  "Start the Symex-TS hydra."
  (interactive)

  ;; Set the current node to the top-most node at point
  (symex-ts-set-current-node-from-point)
  (symex-ts--update-overlay symex-ts--current-node)

  ;; Launch hydra
  (hydra-symex-ts/body))


;; Some edge-casey test data

(list 1 2 (3 4 5) (6 7) (8) 9)

(list 1 2 '(1 2 3) 4)
(list 1 2 #(1 2 3) 4)
(list 1 2 #'(1 2 3) 4)
(list 1 2 '(3) 4)
(list 1 2 #(3) 4)
(list 1 2 #'(3) 4)
(list 1 2 '() 4)
(list 1 2 #() 4)
(list 1 2 #'() 4)

#'() 4

((a 'a)
 (b 'b))

((save-excursion (blah-blah)  ; (<>$
                 (etc))
 (blah-blah)
 (save-excursion
   (blah-blah t)))

((save-excursion (blah-blah)
                 (etc))  ; (<1>$
 (blah-blah)  ; (<2>$
 (save-excursion  ; (<3>$
   (blah-blah t)))

((save-excursion (blah-blah)
                 (etc)))
((save-excursion (blah-blah)
                 
                 
                 (etc))

(blah
  ;; hi
  asdf
  )


(blah
 sdf
 ;; hello
 )

(blah ([abc (blahblah #'etc 'hello)]
       [abc (blahblah #'etc 'hello)]
       [abc (blahblah #'etc 'hello)]))

(blah
 "../blah.etc"
 abc/pqr)
