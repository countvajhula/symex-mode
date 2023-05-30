;;; symex-transformations-ts.el --- An evil way to edit Lisp symbolic expressions as trees -*- lexical-binding: t -*-

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

;; Standard mutative operations to be performed on symexes via Tree
;; Sitter.

;;; Code:

(require 'tree-sitter)
(require 'symex-ts)
(require 'symex-utils)

(defmacro symex-ts--handle-tree-modification (&rest body)
  "Handle modifications to the current Tree Sitter tree after executing BODY.

The buffer's current Tree Sitter tree is saved before BODY is
evaluated. The new tree is then compared and the current node is
selected according to the ranges that have changed."
  (let ((prev-tree (gensym))
        (res (gensym))
        (changed-ranges (gensym))
        (orig-pos (gensym)))

    `(let ((,prev-tree tree-sitter-tree)
           (,orig-pos (point)))

       ;; Execute BODY, bind to RES
       (let ((,res (progn ,@body)))

         ;; Get changes from previous to current tree
         (let ((,changed-ranges (tsc-changed-ranges ,prev-tree tree-sitter-tree)))

           ;; Move point to the first changed range if possible
           (when (and (> (length ,changed-ranges) 0)
                      (> (length (elt ,changed-ranges 0)) 0))
             (let ((new-pos (elt (elt ,changed-ranges 0) 0)))
               ;; don't move point to before the
               ;; original point location
               (if (< new-pos ,orig-pos)
                   (goto-char ,orig-pos)
                 (goto-char new-pos)
                 ;; If the change starts on a carriage return, move
                 ;; forward one character
                 (when (char-equal ?\C-j (char-after))
                   (forward-char 1))))))

         ;; Return the result of evaluating BODY
         ,res))))

(defun symex-ts-clear ()
  "Clear contents of symex."
  (when symex-ts--current-node
    (let ((child-count (tsc-count-named-children symex-ts--current-node)))

      ;; If the node has children, delete them. Otherwise, just delete
      ;; the current node using `symex-ts-delete-node-forward'.
      (if (> child-count 0)
        (let ((first-child (tsc-get-nth-named-child symex-ts--current-node 0))
              (last-child (tsc-get-nth-named-child symex-ts--current-node (1- child-count))))
          (when (and first-child last-child)
            (kill-region (tsc-node-start-position first-child) (tsc-node-end-position last-child))))
        (symex-ts-delete-node-forward 1)))))

(defun symex-ts-comment (&optional count)
  "Comment out COUNT expressions."
  (when (symex-tree-sitter-p)
    (let* ((count (or count 1))
           (node (symex-ts-get-current-node))
           (start-pos (tsc-node-start-position node))
           (end-pos (tsc-node-end-position
                     (if (> count 1)
                         (symex-ts--get-nth-sibling-from-node
                          node
                          #'tsc-get-next-named-sibling count)
                       node))))
      (save-excursion (set-mark start-pos)
                      (goto-char end-pos)
                      (comment-dwim nil))
      (symex-ts-set-current-node-from-point))))

(defun symex-ts--reset-after-delete ()
  "Tidy things up after deletion.

If the deletion results in an empty line it will be removed."
  (when (symex--current-line-empty-p)
    (if (symex--previous-line-empty-p)
        (symex--join-to-non-whitespace)
      (symex--kill-whole-line))))

(defun symex-ts-delete-node-forward (&optional count)
  "Delete COUNT nodes forward from the current node."
  (interactive "p")
  ;; TODO: this is no longer used outside of this module
  (symex-ts--handle-tree-modification
   (let* ((count (or count 1))
          (node (symex-ts-get-current-node))
          (start-pos (tsc-node-start-position node))
          (end-pos (tsc-node-end-position
                    (if (> count 1)
                        (symex-ts--get-nth-sibling-from-node
                         node
                         #'tsc-get-next-named-sibling count)
                      node))))

     ;; Delete the node's region
     (kill-region start-pos end-pos)))
  t)

(defun symex-ts-insert-at-beginning ()
  "Insert at beginning of symex."
  (interactive)
  (when (symex-ts-get-current-node)
    (goto-char (tsc-node-start-position (symex-ts-get-current-node)))))

(defun symex-ts-insert-at-end ()
  "Insert at end of symex."
  (interactive)
  (when (symex-ts-get-current-node)
    (goto-char (tsc-node-end-position (symex-ts-get-current-node)))))

(defun symex-ts-insert-before ()
  "Insert before symex (instead of vim's default at the start of line)."
  (interactive)
  (when (symex-ts-get-current-node)
    (goto-char (tsc-node-start-position (symex-ts-get-current-node)))
    (insert " ")
    (backward-char)))

(defun symex-ts-append-after ()
  "Append after the end of the symex.

Since non-Lisp languages don't really have a syntactic distinction
between the inside and the outside of expressions, this is just an
alias for inserting at the end."
  (interactive)
  (symex-ts-insert-at-end))

(defun symex-ts-append-after ()
  "Append after symex (instead of vim's default of line)."
  (interactive)
  (when (symex-ts-get-current-node)
    (goto-char (tsc-node-end-position (symex-ts-get-current-node)))
    (insert " ")
    (evil-insert-state)))

(defun symex-ts-open-line-after ()
  "Open new line after symex."
  (interactive)
  (when (symex-ts-get-current-node)
    (goto-char (tsc-node-end-position (symex-ts-get-current-node)))
    (newline-and-indent)))

(defun symex-ts-open-line-before ()
  "Open new line before symex."
  (interactive)
  (when (symex-ts-get-current-node)
    (goto-char (tsc-node-start-position (symex-ts-get-current-node)))
    (newline-and-indent)
    (forward-line -1)
    (indent-according-to-mode)
    (move-end-of-line 1)))

(defun symex-ts-emit-forward (count)
  "Emit forward"
  nil)

(defun symex-ts--paste (count direction)
  "Paste before or after symex, COUNT times, according to DIRECTION.

DIRECTION should be either the symbol `before' or `after'."
  (interactive)
  (when (symex-ts-get-current-node)
    (symex-ts--handle-tree-modification (let* ((node (symex-ts-get-current-node))
            (start (tsc-node-start-position node))
            (end (tsc-node-end-position node))
            (indent-start (save-excursion (back-to-indentation) (point)))
            (block-node (or (not (= (line-number-at-pos start) (line-number-at-pos end)))
                            (and (= start indent-start)
                                 (= end (line-end-position))))))
       (goto-char (if (eq direction 'before) start end))
       (dotimes (_ count)
         (when (eq direction 'after) (insert (if block-node "\n" " ")))
         (yank)
         (when (eq direction 'before) (insert (if block-node "\n" " "))
               (indent-according-to-mode)))))))

(defun symex-ts-paste-after (count)
  "Paste after symex, COUNT times."
  (interactive)
  (symex-ts--paste count 'after))

(defun symex-ts-paste-before (count)
  "Paste before symex, COUNT times."
  (interactive)
  (symex-ts--paste count 'before))

(defun symex-ts-replace ()
  "Replace contents of symex."
  (when symex-ts--current-node
    (let* ((child-count (tsc-count-named-children symex-ts--current-node))

           ;; Get new position for insertion: if the node has children
           ;; then the start of the first child node, otherwise the
           ;; current point.
           (new-pos (if (> child-count 0)
                        (tsc-node-start-position (tsc-get-nth-named-child symex-ts--current-node 0))
                      (point))))

      (symex-ts-clear)
      (goto-char new-pos))))

(defun symex-ts-yank (count)
  "Yank (copy) COUNT symexes."
  (interactive "p")
  ;; we set `last-command` here to avoid appending to the kill ring
  ;; when it's a delete followed by a yank. We want to treat each as
  ;; independent entries in the kill ring
  (when (symex-ts-get-current-node)
    (let* ((last-command nil)
           (node (symex-ts-get-current-node))
           (start (tsc-node-start-position node))
           (end (tsc-node-end-position
                 (if (> count 1)
                     (symex-ts--get-nth-sibling-from-node node #'tsc-get-next-named-sibling count)
                   node))))
      (copy-region-as-kill start end))))

(defun symex-ts-tidy ()
  "Auto-indent symex and fix any whitespace."
  ;; Update current node from point and reindent if necessary
  (indent-according-to-mode))


;; TODO: TS: capture node
;; TODO: TS: delete remaining nodes
;; TODO: TS: emit node
;; TODO: TS: shift forward/backward node
;; TODO: TS: splice node
;; TODO: TS: swallow node
;; TODO: TS: wrap node
;; TODO: TS: yank remaining nodes

;; TODO: TS: join node ?
;; TODO: TS: split node ?


(provide 'symex-transformations-ts)
;;; symex-transformations-ts.el ends here
